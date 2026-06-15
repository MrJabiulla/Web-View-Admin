import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const TelzenAdminApp());
}

class TelzenAdminApp extends StatelessWidget {
  const TelzenAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Easy Truck - ETMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F2744)),
        useMaterial3: true,
      ),
      home: const WebViewScreen(),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F2744), Color(0xFF17447A)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.admin_panel_settings,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Easy Truck',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'ETM System',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 50),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _webViewController;
  bool _isInitialPageLoading = true;
  bool _hasError = false;
  String _errorDescription = 'Unable to load page';
  bool _isAtTop = true;
  bool _isRefreshing = false;
  double? _pullStartY;
  double _pullDistance = 0;

  static const double _refreshTriggerDistance = 90;
  static const double _maxPullIndicatorDistance = 76;
  static const MethodChannel _nativeChannel = MethodChannel(
    'etms.easytruck.xyz/native',
  );

  @override
  void initState() {
    super.initState();

    _initializeWebView();

    Future.microtask(() async {
      var status = await Permission.camera.status;
      if (status.isDenied) {
        await Permission.camera.request();
      }
    });
  }

  void _initializeWebView() {
    _webViewController =
        WebViewController(
            onPermissionRequest: (request) {
              request.grant();
            },
          )
          ..setBackgroundColor(Colors.white)
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..addJavaScriptChannel(
            'ScrollTracker',
            onMessageReceived: (message) {
              final atTop = message.message == '1';
              if (_isAtTop != atTop) {
                setState(() => _isAtTop = atTop);
              }
            },
          )
          ..addJavaScriptChannel(
            'EtmsNative',
            onMessageReceived: _handleNativeBridgeMessage,
          )
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageFinished: (String url) {
                setState(() {
                  _isInitialPageLoading = false;
                  _hasError = false;
                  _isRefreshing = false;
                  _pullDistance = 0;
                });
                _webViewController.runJavaScript('''
                  (function() {
                    function report() {
                      ScrollTracker.postMessage(window.scrollY === 0 ? '1' : '0');
                    }
                    window.addEventListener('scroll', report, {passive: true});
                    report();
                  })();
                ''');
                _installNativeBridge();
              },
              onWebResourceError: (WebResourceError error) {
                if (error.isForMainFrame == true) {
                  setState(() {
                    _hasError = true;
                    _errorDescription = _getErrorMessage(error);
                    _isInitialPageLoading = false;
                    _isRefreshing = false;
                    _pullDistance = 0;
                  });
                }
              },
            ),
          )
          ..loadRequest(Uri.parse('https://etms.easytruck.xyz/'));
  }

  Future<void> _handleNativeBridgeMessage(JavaScriptMessage message) async {
    try {
      final payload = jsonDecode(message.message) as Map<String, dynamic>;
      switch (payload['type']) {
        case 'download':
          await _nativeChannel.invokeMethod('saveBase64Download', {
            'fileName': payload['fileName'] ?? 'memo.pdf',
            'mimeType': payload['mimeType'] ?? 'application/octet-stream',
            'base64': payload['base64'] ?? '',
          });
        case 'print':
          await _nativeChannel.invokeMethod('printHtml', {
            'title': payload['title'] ?? 'ETMS Memo',
            'html': payload['html'] ?? '',
          });
      }
    } catch (_) {
      // Keep webpage alerts/errors in control if native bridging fails.
    }
  }

  Future<void> _installNativeBridge() {
    return _webViewController.runJavaScript(r'''
      (function() {
        if (window.__etmsNativeBridgeInstalled) return;
        window.__etmsNativeBridgeInstalled = true;

        function post(payload) {
          if (window.EtmsNative && window.EtmsNative.postMessage) {
            window.EtmsNative.postMessage(JSON.stringify(payload));
          }
        }

        function sendPrintDocument(title, doc) {
          var html = '';
          try {
            html = '<!doctype html>' + doc.documentElement.outerHTML;
          } catch (_) {
            html = '<!doctype html>' + document.documentElement.outerHTML;
          }
          post({
            type: 'print',
            title: title || document.title || 'ETMS Memo',
            html: html
          });
        }

        function installFramePrintBridge(frame) {
          var attempts = 0;
          var timer = setInterval(function() {
            attempts += 1;
            try {
              if (frame.contentWindow && frame.contentDocument) {
                frame.contentWindow.print = function() {
                  sendPrintDocument(frame.contentDocument.title || document.title, frame.contentDocument);
                };
              }
            } catch (_) {}
            if (attempts >= 40) clearInterval(timer);
          }, 50);
        }

        var originalCreateElement = document.createElement.bind(document);
        document.createElement = function(tagName, options) {
          var element = originalCreateElement(tagName, options);
          if (String(tagName).toLowerCase() === 'iframe') {
            installFramePrintBridge(element);
          }
          return element;
        };

        Array.prototype.slice.call(document.querySelectorAll('iframe')).forEach(installFramePrintBridge);

        function sendDataUrlDownload(dataUrl, fileName) {
          var match = /^data:([^;,]+)?(;base64)?,(.*)$/i.exec(dataUrl || '');
          if (!match) return false;
          var mimeType = match[1] || 'application/octet-stream';
          var data = match[3] || '';
          var base64 = match[2] ? data : btoa(decodeURIComponent(data));
          post({
            type: 'download',
            fileName: fileName || 'memo.pdf',
            mimeType: mimeType,
            base64: base64
          });
          return true;
        }

        function sendBlobDownload(blobUrl, fileName) {
          fetch(blobUrl)
            .then(function(response) { return response.blob(); })
            .then(function(blob) {
              var reader = new FileReader();
              reader.onloadend = function() {
                var result = String(reader.result || '');
                sendDataUrlDownload(result, fileName || 'memo.pdf');
              };
              reader.readAsDataURL(blob);
            });
          return true;
        }

        document.addEventListener('click', function(event) {
          var anchor = event.target && event.target.closest
            ? event.target.closest('a[download],a[href^="blob:"],a[href^="data:"]')
            : null;
          if (!anchor) return;

          var href = anchor.href || '';
          var fileName = anchor.getAttribute('download') || 'memo.pdf';
          if (href.indexOf('blob:') === 0) {
            event.preventDefault();
            sendBlobDownload(href, fileName);
          } else if (href.indexOf('data:') === 0 && sendDataUrlDownload(href, fileName)) {
            event.preventDefault();
          }
        }, true);

        var originalCreateObjectURL = URL.createObjectURL.bind(URL);
        URL.createObjectURL = function(blob) {
          var url = originalCreateObjectURL(blob);
          setTimeout(function() {
            var anchors = Array.prototype.slice.call(document.querySelectorAll('a[href="' + url + '"]'));
            anchors.forEach(function(anchor) {
              var fileName = anchor.getAttribute('download') || 'memo.pdf';
              sendBlobDownload(url, fileName);
            });
          }, 0);
          return url;
        };

        window.print = function() {
          sendPrintDocument(document.title || 'ETMS Memo', document);
        };
      })();
    ''');
  }

  String _getErrorMessage(WebResourceError error) {
    switch (error.errorType) {
      case WebResourceErrorType.hostLookup:
      case WebResourceErrorType.connect:
        return 'No internet connection';
      case WebResourceErrorType.timeout:
        return 'Connection timed out';
      default:
        return 'Unable to load page';
    }
  }

  Future<void> _refreshPage() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _hasError = false;
      _pullDistance = _maxPullIndicatorDistance;
    });
    try {
      await _webViewController.reload();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _pullDistance = 0;
        });
      }
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_isAtTop && !_isRefreshing) {
      _pullStartY = event.position.dy;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final startY = _pullStartY;
    if (startY == null || !_isAtTop || _isRefreshing) return;

    final dragDistance = event.position.dy - startY;
    if (dragDistance <= 0) {
      if (_pullDistance != 0) {
        setState(() => _pullDistance = 0);
      }
      return;
    }

    final indicatorDistance = (dragDistance * 0.45).clamp(
      0.0,
      _maxPullIndicatorDistance,
    );
    if ((_pullDistance - indicatorDistance).abs() > 1) {
      setState(() => _pullDistance = indicatorDistance);
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    final shouldRefresh =
        !_isRefreshing && _pullDistance >= _refreshTriggerDistance * 0.45;
    _pullStartY = null;

    if (shouldRefresh) {
      _refreshPage();
    } else if (_pullDistance != 0) {
      setState(() => _pullDistance = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (didPop) return;
        if (await _webViewController.canGoBack()) {
          await _webViewController.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                onPointerDown: _handlePointerDown,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerEnd,
                onPointerCancel: _handlePointerEnd,
                child: WebViewWidget(controller: _webViewController),
              ),
              _PullToRefreshIndicator(
                pullDistance: _pullDistance,
                maxPullDistance: _maxPullIndicatorDistance,
                isRefreshing: _isRefreshing,
              ),
              IgnorePointer(
                ignoring: !_isInitialPageLoading,
                child: AnimatedOpacity(
                  opacity: _isInitialPageLoading ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const SplashScreen(),
                ),
              ),
              if (_hasError)
                _ErrorPage(
                  message: _errorDescription,
                  onRetry: () {
                    setState(() => _hasError = false);
                    _webViewController.reload();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PullToRefreshIndicator extends StatelessWidget {
  const _PullToRefreshIndicator({
    required this.pullDistance,
    required this.maxPullDistance,
    required this.isRefreshing,
  });

  final double pullDistance;
  final double maxPullDistance;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final progress = (pullDistance / maxPullDistance).clamp(0.0, 1.0);
    final isVisible = isRefreshing || progress > 0;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      top: isVisible ? 8 : -48,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: isVisible ? 1 : 0,
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              elevation: 6,
              color: Colors.white,
              shadowColor: Colors.black.withValues(alpha: 0.18),
              shape: const CircleBorder(),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    value: isRefreshing ? null : progress,
                    color: const Color(0xFF0F2744),
                    backgroundColor: const Color(0xFFE5EAF0),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorPage extends StatelessWidget {
  const _ErrorPage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                message == 'No internet connection'
                    ? Icons.wifi_off_rounded
                    : Icons.cloud_off_rounded,
                size: 72,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 24),
              const Text(
                'Connection Error',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F2744),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
