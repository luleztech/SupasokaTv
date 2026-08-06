package com.ayubu.supasoka

import android.content.Intent
import android.os.Bundle
import com.ayubu.supasoka.player.GatewayWebPlayerFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableScreenshotBlocking()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "com.ayubu.supasoka/gateway_web_player",
                GatewayWebPlayerFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
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
                    try {
                        val intent = Intent(this, SupasokaNativePlayerActivity::class.java)
                        intent.putExtra("url", args["url"]?.toString().orEmpty())
                        intent.putExtra("licenseUrl", args["licenseUrl"]?.toString().orEmpty())
                        intent.putExtra("token", args["token"]?.toString().orEmpty())
                        intent.putExtra("drmType", args["drmType"]?.toString().orEmpty().ifEmpty { "NONE" })
                        val mergedClearKey = sequenceOf(
                            args["clearKeyHex"]?.toString(),
                            args["drmClearKey"]?.toString(),
                            args["drm_clear_key"]?.toString(),
                        ).firstOrNull { !it.isNullOrBlank() }.orEmpty()
                        intent.putExtra("clearKeyHex", mergedClearKey)
                        intent.putExtra("headersJson", args["headersJson"]?.toString().orEmpty())
                        intent.putExtra(
                            "audioLanguage",
                            args["audioLanguage"]?.toString().orEmpty().ifEmpty { "sw" },
                        )
                        intent.putExtra("channelId", (args["channelId"] as? Number)?.toInt() ?: -1)
                        intent.putExtra("channelName", args["channelName"]?.toString().orEmpty())
                        intent.putExtra(
                            "fallbackStreamsJson",
                            args["fallbackStreamsJson"]?.toString().orEmpty(),
                        )
                        intent.putExtra(
                            "playbackEngine",
                            args["playbackEngine"]?.toString().orEmpty(),
                        )
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("native_open_failed", e.message ?: "Failed to open player", null)
                    }
                }
                "updatePlayerConfig" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }
}
