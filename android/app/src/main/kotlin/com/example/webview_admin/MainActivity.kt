package com.etms.webview_admin

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.print.PrintAttributes
import android.print.PrintManager
import android.provider.MediaStore
import android.util.Base64
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "etms.easytruck.xyz/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveBase64Download" -> {
                        val fileName = call.argument<String>("fileName") ?: "memo.pdf"
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        val base64Data = call.argument<String>("base64") ?: ""

                        try {
                            saveBase64Download(fileName, mimeType, base64Data)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("SAVE_FAILED", error.message, null)
                        }
                    }
                    "printHtml" -> {
                        val html = call.argument<String>("html") ?: ""
                        val title = call.argument<String>("title") ?: "ETMS Memo"

                        try {
                            printHtml(title, html)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("PRINT_FAILED", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveBase64Download(fileName: String, mimeType: String, base64Data: String) {
        val bytes = Base64.decode(base64Data.substringAfter("base64,", base64Data), Base64.DEFAULT)
        val safeFileName = fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, safeFileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri: Uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Unable to create download file")

            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Unable to open download file")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } else {
            val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloads.exists()) downloads.mkdirs()
            FileOutputStream(File(downloads, safeFileName)).use { it.write(bytes) }
        }
    }

    private fun printHtml(title: String, html: String) {
        val printWebView = WebView(this)
        printWebView.webViewClient = object : android.webkit.WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                val printManager = getSystemService(Context.PRINT_SERVICE) as PrintManager
                val adapter = view.createPrintDocumentAdapter(title)
                printManager.print(title, adapter, PrintAttributes.Builder().build())
            }
        }
        printWebView.loadDataWithBaseURL("https://etms.easytruck.xyz/", html, "text/html", "UTF-8", null)
    }
}
