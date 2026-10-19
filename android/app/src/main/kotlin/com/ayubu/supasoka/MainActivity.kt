package com.ayubu.supasoka

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import com.ayubu.supasoka.player.GatewayWebPlayerFactory
import com.ayubu.supasoka.player.PlaybackPreferences
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableScreenshotBlocking()
        // Warm WebView engine so gateway pages start faster.
        Handler(Looper.getMainLooper()).post {
            try {
                WebView(applicationContext).apply {
                    settings.javaScriptEnabled = true
                    loadUrl("about:blank")
                    destroy()
                }
            } catch (_: Exception) {
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ayubu.supasoka/security_guard",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "findCaptureApps" -> result.success(
                    CaptureProtection.findEnabledCaptureApps(this).map {
                        mapOf("packageName" to it.packageName, "label" to it.label)
                    },
                )
                "openCaptureAppSettings" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName == null || CaptureProtection.findEnabledCaptureApps(this)
                            .none { it.packageName == packageName }
                    ) {
                        result.error("invalid_package", "No enabled capture app found", null)
                    } else {
                        val intent = Intent(
                            android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.parse("package:$packageName"),
                        )
                        runCatching { startActivity(intent) }
                            .onSuccess { result.success(null) }
                            .onFailure { result.error("settings_failed", it.message, null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
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
                        val intent = Intent(this, OrizonPlayerActivity::class.java)
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
                        val prefs = PlaybackPreferences.current()
                        intent.putExtra(
                            "dataSaver",
                            (args["dataSaver"] as? Boolean) ?: prefs.dataSaver,
                        )
                        intent.putExtra(
                            "defaultQuality",
                            args["defaultQuality"]?.toString().orEmpty().ifEmpty { prefs.defaultQuality },
                        )
                        intent.putExtra(
                            "videoZoomMode",
                            args["videoZoomMode"]?.toString().orEmpty().ifEmpty { prefs.videoZoomMode },
                        )
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("native_open_failed", e.message ?: "Failed to open player", null)
                    }
                }
                "updatePlayerConfig" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?>
                    val current = PlaybackPreferences.current()
                    PlaybackPreferences.update(
                        dataSaver = current.dataSaver,
                        defaultQuality = args?.get("defaultQuality")?.toString().orEmpty()
                            .ifEmpty { current.defaultQuality },
                        videoZoomMode = current.videoZoomMode,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
