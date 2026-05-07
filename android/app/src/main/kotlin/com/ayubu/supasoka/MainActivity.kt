package com.ayubu.supasoka

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        enableScreenshotBlocking()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ayubu.supasoka/native_player",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?>
                    if (args == null) {
                        result.error("bad_args", "Expected map", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, SupasokaNativePlayerActivity::class.java)
                    intent.putExtra("url", args["url"]?.toString().orEmpty())
                    intent.putExtra("licenseUrl", args["licenseUrl"]?.toString().orEmpty())
                    intent.putExtra("token", args["token"]?.toString().orEmpty())
                    intent.putExtra("drmType", args["drmType"]?.toString().orEmpty().ifEmpty { "NONE" })
                    intent.putExtra("clearKeyHex", args["clearKeyHex"]?.toString().orEmpty())
                    intent.putExtra("headersJson", args["headersJson"]?.toString().orEmpty())
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
