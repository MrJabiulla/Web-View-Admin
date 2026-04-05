import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const TruckAdminApp());
}

class TruckAdminApp extends StatelessWidget {
  const TruckAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Truck Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFED600)),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate to WebView after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const WebViewScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFED600),
              const Color(0xFFFDFFC0),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo/Icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.admin_panel_settings,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 30),
              // App Title
              const Text(
                'Truck Admin',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              // Subtitle
              const Text(
                'Admin Panel',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 50),
              // Loading indicator
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
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
  bool isLoading = true;
  double _zoomLevel = 1.0;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Enable cookies to persist credentials
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => isLoading = false);
            _injectSavedCredentials();
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      // Change this URL to your actual admin panel URL
      ..loadRequest(Uri.parse('https://admin.easytruck.xyz/'));
  }

  // Save credentials to local storage
  Future<void> _saveCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_email', email);
    await prefs.setString('saved_password', password);
    debugPrint('Credentials saved locally');
  }

  // Retrieve saved credentials
  Future<Map<String, String>> _getCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('saved_email') ?? '';
    final password = prefs.getString('saved_password') ?? '';
    return {'email': email, 'password': password};
  }

  // Inject saved credentials into login form
  Future<void> _injectSavedCredentials() async {
    final credentials = await _getCredentials();
    if (credentials['email']!.isNotEmpty && credentials['password']!.isNotEmpty) {
      // Autofill credentials (can be customized based on your form's input IDs)
      await _webViewController.runJavaScript('''
        document.querySelectorAll('input[type="email"], input[type="text"]')[0].value = "${credentials['email']}";
        document.querySelectorAll('input[type="password"]')[0].value = "${credentials['password']}";
      ''');
    }
  }

  // Clear saved credentials
  Future<void> _clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_email');
    await prefs.remove('saved_password');
    debugPrint('Credentials cleared');
  }

  void _zoomOut() {
    if (_zoomLevel > 0.5) {
      _zoomLevel -= 0.1;
      setState(() {});
    }
  }

  void _zoomIn() {
    if (_zoomLevel < 3.0) {
      _zoomLevel += 0.1;
      setState(() {});
    }
  }

  void _resetZoom() {
    _zoomLevel = 1.0;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Transform.scale(
            scale: _zoomLevel,
            alignment: Alignment.topCenter,
            child: WebViewWidget(controller: _webViewController),
          ),
          if (isLoading)
            Container(
              color: Colors.white.withOpacity(0.7),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
