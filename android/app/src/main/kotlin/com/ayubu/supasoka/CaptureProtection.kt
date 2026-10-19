package com.ayubu.supasoka

import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri

/** Detects a small, explicit set of known Android traffic-capture apps. */
internal object CaptureProtection {
    private val capturePackages = listOf(
        "com.reqable.android",
        "com.guoshi.httpcanary",
        "com.guoshi.httpcanary.premium",
        "com.guoshi.httpcanary.premium.pro",
        "com.emanuelef.remote_capture", // PCAPdroid
        "app.greyshirts.sslcapture", // Packet Capture
        "tech.httptoolkit.android.v1",
    )

    data class DetectedApp(val packageName: String, val label: String)

    fun findEnabledCaptureApps(context: Context): List<DetectedApp> = capturePackages.mapNotNull { packageName ->
        try {
            val info = context.packageManager.getApplicationInfo(packageName, 0)
            if (!info.enabled) return@mapNotNull null
            DetectedApp(
                packageName = packageName,
                label = context.packageManager.getApplicationLabel(info).toString(),
            )
        } catch (_: PackageManager.NameNotFoundException) {
            null
        } catch (_: RuntimeException) {
            null
        }
    }
}

/** Keep signed stream paths and query tokens out of Logcat. */
internal fun safeUrlForLogs(rawUrl: String): String {
    val uri = runCatching { Uri.parse(rawUrl) }.getOrNull() ?: return "<url>"
    val scheme = uri.scheme ?: return "<url>"
    val host = uri.host ?: return "<url>"
    return "$scheme://$host"
}
