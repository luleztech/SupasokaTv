package com.ayubu.supasoka.player

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import com.ayubu.supasoka.domain.model.DrmType
import com.ayubu.supasoka.domain.model.StreamSession
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Loads a PHP/HTML gateway in a **hidden** WebView (never attached to the UI), then:
 * 1) intercepts `.m3u8` / `.mpd` requests, and/or
 * 2) reads page HTML and decrypts `encryptedMpd` / `keyPart`,
 * so playback can continue in ExoPlayer without showing Google reCAPTCHA.
 */
object GatewayWebViewExtractor {
    private const val TAG = "GatewayWebExtract"
    private const val DEFAULT_TIMEOUT_MS = 14_000L
    private val mainHandler = Handler(Looper.getMainLooper())

    fun extractAsync(
        context: Context,
        session: StreamSession,
        timeoutMs: Long = DEFAULT_TIMEOUT_MS,
        onResult: (GatewayPlaybackResolver.Resolved?) -> Unit,
    ) {
        val appCtx = context.applicationContext
        if (Looper.myLooper() == Looper.getMainLooper()) {
            start(appCtx, session, timeoutMs, onResult)
        } else {
            mainHandler.post { start(appCtx, session, timeoutMs, onResult) }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun start(
        context: Context,
        session: StreamSession,
        timeoutMs: Long,
        onResult: (GatewayPlaybackResolver.Resolved?) -> Unit,
    ) {
        val gatewayUrl = session.mpdUrl.trim()
        if (gatewayUrl.isEmpty() || !StreamUrlClassifier.needsWebPlayer(gatewayUrl)) {
            onResult(null)
            return
        }

        val done = AtomicBoolean(false)
        var webView: WebView? = null
        var intercepted: GatewayPlaybackResolver.Resolved? = null
        val audioLang = session.preferredAudioLanguage.ifBlank { "sw" }
        val reqHeaders = PlaybackBrowserHeaders.buildForUrl(gatewayUrl, session.headers, audioLang)
        if (session.token.isNotBlank() &&
            !reqHeaders.keys.any { it.equals("Authorization", ignoreCase = true) }
        ) {
            reqHeaders["Authorization"] = "Bearer ${session.token}"
        }

        fun finish(result: GatewayPlaybackResolver.Resolved?) {
            if (!done.compareAndSet(false, true)) return
            try {
                webView?.stopLoading()
                webView?.loadUrl("about:blank")
                webView?.destroy()
            } catch (_: Exception) {
            }
            webView = null
            Log.i(TAG, if (result != null) "Extracted via hidden WebView" else "Hidden WebView extract failed")
            onResult(result)
        }

        val timeout = Runnable { finish(intercepted) }
        mainHandler.postDelayed(timeout, timeoutMs)

        try {
            webView = WebView(context).apply {
                // Never attach to a window — keeps reCAPTCHA off-screen.
                setWillNotDraw(true)
                settings.apply {
                    javaScriptEnabled = true
                    domStorageEnabled = true
                    databaseEnabled = true
                    mediaPlaybackRequiresUserGesture = false
                    mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                    userAgentString = PlaybackBrowserHeaders.CHROME_MOBILE_UA
                    // Block network images — less captcha chrome.
                    blockNetworkImage = true
                }
                CookieManager.getInstance().setAcceptCookie(true)
                CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)

                webViewClient = object : WebViewClient() {
                    override fun shouldInterceptRequest(
                        view: WebView?,
                        request: WebResourceRequest?,
                    ): WebResourceResponse? {
                        val u = request?.url?.toString().orEmpty()
                        if (u.isNotEmpty() && looksLikeManifest(u) && !u.contains("recaptcha", ignoreCase = true)) {
                            val isHls = u.lowercase().contains(".m3u8")
                            Log.i(TAG, "Intercepted manifest ${u.take(96)}")
                            intercepted = GatewayPlaybackResolver.Resolved(
                                streamUrl = u,
                                isHls = isHls,
                                headers = LinkedHashMap(reqHeaders),
                                licenseUrl = session.licenseUrl,
                                authToken = session.token,
                            )
                            mainHandler.post {
                                mainHandler.removeCallbacks(timeout)
                                finish(intercepted)
                            }
                        }
                        return super.shouldInterceptRequest(view, request)
                    }

                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        if (done.get()) return
                        view?.evaluateJavascript(
                            "(function(){try{return document.documentElement.outerHTML;}catch(e){return '';}})();",
                        ) { raw ->
                            if (done.get()) return@evaluateJavascript
                            val html = unescapeJsString(raw)
                            if (html.isBlank()) return@evaluateJavascript
                            Log.d(
                                TAG,
                                "Hidden page htmlLen=${html.length} recaptcha=${html.contains("recaptcha", true)} " +
                                    "encrypted=${html.contains("encrypted", true)} keyPart=${html.contains("keyPart", true)}",
                            )
                            val resolved = resolveFromHtml(html, gatewayUrl, session, reqHeaders)
                            if (resolved != null) {
                                mainHandler.removeCallbacks(timeout)
                                finish(resolved)
                            }
                        }
                    }
                }
            }
            Log.i(TAG, "Loading hidden gateway ${gatewayUrl.take(80)}")
            webView?.loadUrl(gatewayUrl, reqHeaders)
        } catch (e: Exception) {
            Log.w(TAG, "Hidden WebView start failed: ${e.message}")
            mainHandler.removeCallbacks(timeout)
            finish(null)
        }
    }

    private fun looksLikeManifest(url: String): Boolean {
        val u = url.lowercase()
        if (u.contains("recaptcha") || u.contains("google.com/recaptcha")) return false
        return u.contains(".m3u8") || u.contains(".mpd") ||
            (u.contains("/manifest") && (u.contains("dash") || u.contains("hls") || u.contains("mpeg")))
    }

    private fun resolveFromHtml(
        html: String,
        gatewayUrl: String,
        session: StreamSession,
        reqHeaders: Map<String, String>,
    ): GatewayPlaybackResolver.Resolved? {
        val encrypted = GatewayStreamExtractor.extract(html)
            ?: GatewayStreamExtractor.extractDrmFromHtml(html)
        if (encrypted != null && encrypted.streamUrl.lowercase().startsWith("http")) {
            val merged = LinkedHashMap(reqHeaders)
            if (encrypted.authToken.isNotEmpty() &&
                !merged.keys.any { it.equals("Authorization", ignoreCase = true) }
            ) {
                merged["Authorization"] = "Bearer ${encrypted.authToken}"
            }
            val license = encrypted.licenseUrl.ifBlank { session.licenseUrl }
            var drm: DrmType? = null
            if (session.drmType != DrmType.NONE) {
                drm = session.drmType
            } else if (license.isNotBlank()) {
                drm = if (license.lowercase().contains("playready")) DrmType.PLAYREADY else DrmType.WIDEVINE
            } else if (encrypted.clearKeyRaw.isNotBlank()) {
                drm = DrmType.CLEARKEY
            }
            return GatewayPlaybackResolver.Resolved(
                streamUrl = encrypted.streamUrl,
                licenseUrl = license,
                authToken = encrypted.authToken.ifBlank { session.token },
                clearKeyRaw = encrypted.clearKeyRaw,
                isHls = encrypted.isHls,
                headers = merged,
                drmType = drm,
            )
        }
        val manifest = ManifestUrlExtractor.extract(html, gatewayUrl) ?: return null
        return GatewayPlaybackResolver.Resolved(
            streamUrl = manifest.url,
            isHls = manifest.isHls,
            headers = LinkedHashMap(reqHeaders),
            licenseUrl = session.licenseUrl,
            authToken = session.token,
        )
    }

    /** evaluateJavascript returns a JSON-encoded string (quotes + escapes). */
    private fun unescapeJsString(raw: String?): String {
        if (raw.isNullOrBlank() || raw == "null") return ""
        var s = raw.trim()
        if (s.length >= 2 && s.first() == '"' && s.last() == '"') {
            s = s.substring(1, s.length - 1)
        }
        return s
            .replace("\\u003C", "<")
            .replace("\\u003c", "<")
            .replace("\\u003E", ">")
            .replace("\\u003e", ">")
            .replace("\\\"", "\"")
            .replace("\\'", "'")
            .replace("\\n", "\n")
            .replace("\\r", "\r")
            .replace("\\t", "\t")
            .replace("\\\\", "\\")
    }
}
