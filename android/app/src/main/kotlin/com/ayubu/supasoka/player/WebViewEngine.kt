package com.ayubu.supasoka.player

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.ayubu.supasoka.domain.model.PlaybackState
import com.ayubu.supasoka.domain.model.StreamQuality
import com.ayubu.supasoka.domain.model.StreamSession

/**
 * WebView engine for PHP / gateway pages. Quality and audio are applied via
 * [GatewayPlaybackJs] against in-page Shaka / hls.js players.
 */
class WebViewEngine(
    private val context: Context,
    private val onPlaybackStateChanged: (PlaybackState) -> Unit,
    private val onError: (String) -> Unit,
    private val onHumanCheck: (Boolean) -> Unit = {},
) {
    private var webView: WebView? = null
    private var currentSession: StreamSession? = null
    private var jsInterface: WebViewJsInterface? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var playbackStarted = false
    private var userPaused = false
    private var forceAutoplayGeneration = -1
    private var playbackApisInjected = false
    private var userPickedQuality = false
    private var qualityConfirmed = false
    private var qualityRetryGeneration = 0
    private var selectedQuality: StreamQuality = StreamQuality.AUTO
    private var preferredAudioLanguage = "sw"
    private var lastLoadedAudioLanguage = ""
    private var audioLanguageConfirmed = false
    private var pageLoadGeneration = 0
    private var pageFinishRunnable: Runnable? = null
    private var captchaPollRunnable: Runnable? = null
    private var classifyPollRunnable: Runnable? = null
    private var humanCheckActive = false
    private var captchaTokenSeen = false
    private var captchaReloadAttempted = false
    private val pendingRunnables = mutableListOf<Runnable>()

    companion object {
        private const val TAG = "EaMaxAudio"
        private const val QUALITY_TAG = "EaMaxQuality"
        private const val CLASSIFY_MAX_ATTEMPTS = 16
    }

    private fun shouldUseWebView(url: String): Boolean =
        StreamUrlClassifier.needsWebPlayer(url)

    private fun buildLoadHeaders(
        session: StreamSession,
        audioLang: String = preferredAudioLanguage,
    ): Map<String, String> {
        val lang = normalizeAudioLanguage(audioLang)
        val h = PlaybackBrowserHeaders.buildForUrl(session.mpdUrl, session.headers, lang)
        if (session.token.isNotBlank() &&
            !h.keys.any { it.equals("Authorization", ignoreCase = true) }
        ) {
            h["Authorization"] = "Bearer ${session.token}"
        }
        return h
    }

    fun initialize(streamSession: StreamSession) {
        currentSession = streamSession
        playbackStarted = false
        userPaused = false
        forceAutoplayGeneration = -1
        playbackApisInjected = false
        userPickedQuality = false
        qualityConfirmed = false
        qualityRetryGeneration++
        captchaTokenSeen = false
        captchaReloadAttempted = false
        preferredAudioLanguage = normalizeAudioLanguage(streamSession.preferredAudioLanguage)
        lastLoadedAudioLanguage = preferredAudioLanguage
        cancelPendingRunnables()
        stopClassifyPoll()
        stopCaptchaPoll()

        val url = streamSession.mpdUrl
        val headers = buildLoadHeaders(streamSession, preferredAudioLanguage)
        val isExternalWebPage = shouldUseWebView(url)

        Log.d(TAG, "initialize url=${url.take(60)} audio=$preferredAudioLanguage " +
            "Accept-Language=${headers["Accept-Language"]}")

        try {
            webView = WebView(context).apply {
                setLayerType(View.LAYER_TYPE_HARDWARE, null)

                settings.apply {
                    javaScriptEnabled = true
                    domStorageEnabled = true
                    databaseEnabled = true
                    allowFileAccess = true
                    allowContentAccess = true
                    allowFileAccessFromFileURLs = true
                    allowUniversalAccessFromFileURLs = true
                    mediaPlaybackRequiresUserGesture = false
                    mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                    setSupportMultipleWindows(true)
                    javaScriptCanOpenWindowsAutomatically = true
                    loadWithOverviewMode = true
                    useWideViewPort = true
                    builtInZoomControls = false
                    displayZoomControls = false
                    setSupportZoom(false)
                    textZoom = 100
                    userAgentString = PlaybackBrowserHeaders.CHROME_MOBILE_UA
                }
                setInitialScale(100)

                CookieManager.getInstance().setAcceptCookie(true)
                CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                // Keep gateway + Google reCAPTCHA cookies across channel opens.
                try {
                    CookieManager.getInstance().flush()
                } catch (_: Exception) {
                }

                // Player hooks only — never stub/hide reCAPTCHA in the visible WebView.
                installDocumentStartHooks(this)

                webViewClient = object : WebViewClient() {
                    override fun onPageStarted(
                        view: WebView?,
                        startedUrl: String?,
                        favicon: android.graphics.Bitmap?,
                    ) {
                        pageLoadGeneration++
                        pageFinishRunnable?.let { mainHandler.removeCallbacks(it) }
                        pageFinishRunnable = null
                        stopClassifyPoll()
                        stopCaptchaPoll()
                        // Keep human-check UI if a reload was triggered after token
                        // (common PHP gateways reload once verification succeeds).
                        if (humanCheckActive && !captchaTokenSeen) {
                            humanCheckActive = false
                            onHumanCheck(false)
                        }
                        playbackStarted = false
                        playbackApisInjected = false
                        audioLanguageConfirmed = false
                        drm4012Handled = false
                        // Patch execute() to wait for checkbox; do NOT hide the widget.
                        injectRecaptchaUnlockHelper()
                        injectPlayerCaptureHook()
                        injectWidevineL3Fallback()
                        onPlaybackStateChanged(PlaybackState.BUFFERING)
                    }

                    override fun onPageFinished(view: WebView?, finishedUrl: String?) {
                        super.onPageFinished(view, finishedUrl)
                        if (!isExternalWebPage) return
                        injectRecaptchaUnlockHelper()
                        webView?.evaluateJavascript(
                            GatewayPlaybackJs.ensureCaptchaChallengeVisibleScript(),
                            null,
                        )
                        val gen = pageLoadGeneration
                        pageFinishRunnable?.let { mainHandler.removeCallbacks(it) }
                        val r = Runnable {
                            if (gen != pageLoadGeneration) return@Runnable
                            classifyPageThenReady(gen, attempt = 0)
                        }
                        pageFinishRunnable = r
                        mainHandler.postDelayed(r, 350)
                    }

                    override fun onReceivedError(
                        view: WebView?,
                        request: android.webkit.WebResourceRequest?,
                        error: android.webkit.WebResourceError?,
                    ) {
                        if (request?.isForMainFrame == true) {
                            onError("WebView Error: ${error?.description}")
                        }
                    }
                }

                webChromeClient = object : WebChromeClient() {
                    override fun onConsoleMessage(
                        consoleMessage: android.webkit.ConsoleMessage?,
                    ): Boolean {
                        val msg = consoleMessage?.message().orEmpty()
                        Log.d(
                            "ShakaConsole",
                            "[${consoleMessage?.messageLevel()}] $msg",
                        )
                        // Shaka 4012 = RESTRICTIONS_CANNOT_BE_MET (often HDCP / L1-only video).
                        if (msg.contains("4012") && msg.contains("Shaka", ignoreCase = true)) {
                            mainHandler.post { handleDrmRestrictedError() }
                        }
                        return true
                    }
                }

                jsInterface = WebViewJsInterface(
                    onPlaybackStateChanged = onPlaybackStateChanged,
                    onError = onError,
                    onAudioProbe = { wanted, applied ->
                        if (applied && wanted == preferredAudioLanguage) {
                            audioLanguageConfirmed = true
                        }
                    },
                    onQualityProbe = { wanted, maxH, activeH, applied ->
                        val expected = qualityModeFor(selectedQuality)
                        // Ignore stale probes from a previous quality pick.
                        if (applied && wanted == expected) {
                            qualityConfirmed = true
                            Log.d(QUALITY_TAG, "quality confirmed wanted=$wanted maxH=$maxH activeH=$activeH")
                        }
                    },
                )
                addJavascriptInterface(jsInterface!!, "ShakaPlayerBridge")
            }

            val wv = webView ?: return
            headers["User-Agent"]?.let { wv.settings.userAgentString = it }
            if (isExternalWebPage) {
                wv.loadUrl(url, headers)
                onPlaybackStateChanged(PlaybackState.BUFFERING)
            } else {
                wv.loadUrl("about:blank")
            }
        } catch (e: Exception) {
            onError("Failed to initialize WebView: ${e.message}")
        }
    }

    /**
     * Visible WebView: wait for a real checkbox token. Do not stub or hide reCAPTCHA —
     * hiding left users stuck on "verify you are not a robot" with no box to tick.
     */
    private fun injectRecaptchaUnlockHelper() {
        webView?.evaluateJavascript(GatewayPlaybackJs.checkboxRecaptchaUnlockScript(), null)
    }

    private fun installDocumentStartHooks(wv: WebView) {
        try {
            if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                WebViewCompat.addDocumentStartJavaScript(
                    wv,
                    GatewayPlaybackJs.checkboxRecaptchaUnlockScript() + "\n" +
                        GatewayPlaybackJs.playerCaptureHookScript() + "\n" +
                        GatewayPlaybackJs.widevineL3FallbackScript(),
                    setOf("*"),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "document-start hooks unavailable: ${e.message}")
        }
    }

    private fun injectPlayerCaptureHook() {
        webView?.evaluateJavascript(GatewayPlaybackJs.playerCaptureHookScript(), null)
    }

    private fun classifyPageThenReady(gen: Int, attempt: Int) {
        if (gen != pageLoadGeneration) return
        injectRecaptchaUnlockHelper()
        webView?.evaluateJavascript(GatewayPlaybackJs.ensureCaptchaChallengeVisibleScript(), null)
        webView?.evaluateJavascript(GatewayPlaybackJs.pageCaptchaStateScript()) { raw ->
            if (gen != pageLoadGeneration) return@evaluateJavascript
            val status = raw?.trim()?.trim('"')?.lowercase().orEmpty()
            Log.d(TAG, "pageCaptchaState attempt=$attempt → $status")
            when (status) {
                "playing" -> {
                    stopClassifyPoll()
                    persistGatewayCookies()
                    exitCaptchaModeIfNeeded()
                    handlePageReady()
                }
                "captcha", "token" -> {
                    stopClassifyPoll()
                    if (status == "token") captchaTokenSeen = true
                    enterCaptchaMode(gen)
                    if (status == "token") maybeReloadAfterCaptchaToken(gen)
                }
                "waiting" -> {
                    if (attempt < CLASSIFY_MAX_ATTEMPTS) {
                        scheduleClassifyRetry(gen, attempt + 1)
                    } else {
                        Log.i(TAG, "No player after wait — entering human-check fallback")
                        stopClassifyPoll()
                        enterCaptchaMode(gen)
                    }
                }
                else -> {
                    if (attempt < 4) {
                        scheduleClassifyRetry(gen, attempt + 1)
                    } else {
                        stopClassifyPoll()
                        exitCaptchaModeIfNeeded()
                        handlePageReady()
                    }
                }
            }
        }
    }

    private fun scheduleClassifyRetry(gen: Int, attempt: Int) {
        stopClassifyPoll()
        val r = Runnable {
            if (gen != pageLoadGeneration) return@Runnable
            classifyPageThenReady(gen, attempt)
        }
        classifyPollRunnable = r
        mainHandler.postDelayed(r, 500)
    }

    private fun stopClassifyPoll() {
        classifyPollRunnable?.let { mainHandler.removeCallbacks(it) }
        classifyPollRunnable = null
    }

    private fun enterCaptchaMode(gen: Int) {
        if (gen != pageLoadGeneration) return
        Log.i(TAG, "Human check required — revealing reCAPTCHA for user")
        if (!humanCheckActive) {
            humanCheckActive = true
            onHumanCheck(true)
        }
        // Soft layer avoids white/half tiles on some Huawei WebViews during challenge.
        try {
            webView?.setLayerType(View.LAYER_TYPE_NONE, null)
        } catch (_: Exception) {
        }
        webView?.evaluateJavascript(GatewayPlaybackJs.ensureCaptchaChallengeVisibleScript(), null)
        injectRecaptchaUnlockHelper()
        injectPlayerCaptureHook()
        injectWidevineL3Fallback()
        onPlaybackStateChanged(PlaybackState.BUFFERING)
        startCaptchaPoll(gen)
    }

    private fun startCaptchaPoll(gen: Int) {
        stopCaptchaPoll()
        var attempts = 0
        val poll = object : Runnable {
            override fun run() {
                if (gen != pageLoadGeneration) return
                attempts++
                injectRecaptchaUnlockHelper()
                // Gentle visibility only — never strip challenge iframe width/height.
                if (attempts == 1 || attempts % 4 == 0) {
                    webView?.evaluateJavascript(
                        GatewayPlaybackJs.ensureCaptchaChallengeVisibleScript(),
                        null,
                    )
                }
                webView?.evaluateJavascript(GatewayPlaybackJs.pageCaptchaStateScript()) { raw ->
                    if (gen != pageLoadGeneration) return@evaluateJavascript
                    val status = raw?.trim()?.trim('"')?.lowercase().orEmpty()
                    when (status) {
                        "playing" -> {
                            Log.i(TAG, "Human check cleared ($status) — starting playback")
                            persistGatewayCookies()
                            exitCaptchaModeIfNeeded()
                            handlePageReady()
                        }
                        "token" -> {
                            captchaTokenSeen = true
                            Log.i(TAG, "reCAPTCHA token received — waiting for player unlock")
                            maybeReloadAfterCaptchaToken(gen)
                            if (attempts < 240) {
                                captchaPollRunnable = this
                                mainHandler.postDelayed(this, 400)
                            }
                        }
                        "captcha", "waiting" -> {
                            if (attempts < 240) {
                                captchaPollRunnable = this
                                mainHandler.postDelayed(this, 400)
                            } else {
                                Log.w(TAG, "Human check still pending after timeout — keep UI clear")
                            }
                        }
                        else -> {
                            if (attempts < 240) {
                                captchaPollRunnable = this
                                mainHandler.postDelayed(this, 400)
                            } else {
                                Log.w(TAG, "Human check still pending after timeout — keep UI clear")
                            }
                        }
                    }
                }
            }
        }
        captchaPollRunnable = poll
        mainHandler.postDelayed(poll, 300)
    }

    /**
     * Some gateways only unlock after a full reload once the checkbox token exists.
     * Reload once so the channel opens after the user completes reCAPTCHA.
     */
    private fun maybeReloadAfterCaptchaToken(gen: Int) {
        if (gen != pageLoadGeneration || captchaReloadAttempted) return
        captchaReloadAttempted = true
        persistGatewayCookies()
        val session = currentSession ?: return
        val wv = webView ?: return
        Log.i(TAG, "Reloading gateway once after reCAPTCHA token")
        mainHandler.postDelayed({
            if (gen != pageLoadGeneration) return@postDelayed
            val headers = buildLoadHeaders(session, preferredAudioLanguage)
            headers["User-Agent"]?.let { wv.settings.userAgentString = it }
            wv.loadUrl(session.mpdUrl, headers)
        }, 700)
    }

    private fun persistGatewayCookies() {
        try {
            CookieManager.getInstance().flush()
        } catch (_: Exception) {
        }
        val host = runCatching {
            android.net.Uri.parse(currentSession?.mpdUrl.orEmpty()).host
        }.getOrNull().orEmpty()
        if (host.isNotBlank()) {
            GatewayCaptchaSession.markSolved(context, host)
        }
    }

    private fun exitCaptchaModeIfNeeded() {
        if (!humanCheckActive) {
            onHumanCheck(false)
            return
        }
        humanCheckActive = false
        onHumanCheck(false)
    }

    private fun stopCaptchaPoll() {
        captchaPollRunnable?.let { mainHandler.removeCallbacks(it) }
        captchaPollRunnable = null
    }

    private fun handlePageReady() {
        Log.d(TAG, "page ready — autoplay audio=$preferredAudioLanguage")
        captchaTokenSeen = false
        persistGatewayCookies()
        try {
            webView?.setLayerType(View.LAYER_TYPE_HARDWARE, null)
        } catch (_: Exception) {
        }
        injectRecaptchaUnlockHelper()
        injectPlayerCaptureHook()
        injectWidevineL3Fallback()
        injectFitPlaybackToScreen()
        ensurePlaybackApisInjected()
        nudgeVideoPlay()
        applyQualityAfterPageLoad()
        audioLanguageConfirmed = false
        applyAudioLanguageJs(preferredAudioLanguage, scheduleRetries = true)
        onPlaybackStateChanged(PlaybackState.PLAYING)
        playbackStarted = true
        userPaused = false
        scheduleForceAutoplay(pageLoadGeneration, 0)
    }

    private fun injectFitPlaybackToScreen() {
        webView?.evaluateJavascript(GatewayPlaybackJs.fitPlaybackToScreenScript(), null)
    }

    private fun injectWidevineL3Fallback() {
        webView?.evaluateJavascript(GatewayPlaybackJs.widevineL3FallbackScript(), null)
    }

    private var drm4012Handled = false

    private fun handleDrmRestrictedError() {
        if (drm4012Handled) return
        drm4012Handled = true
        Log.w(QUALITY_TAG, "Shaka 4012 DRM restricted — clearing app restrictions + L3")
        injectWidevineL3Fallback()
        webView?.evaluateJavascript(
            "try{window.__supasokaHandleDrm4012&&window.__supasokaHandleDrm4012();}catch(e){}",
            null,
        )
        postDelayed({
            injectWidevineL3Fallback()
            if (!userPaused) play()
        }, 500)
    }

    /** Keep forcing play until the video is actually running (no user gesture needed). */
    private fun scheduleForceAutoplay(gen: Int, attempt: Int) {
        if (gen != pageLoadGeneration) return
        if (humanCheckActive || userPaused) return
        if (attempt > 6) return
        forceAutoplayGeneration = gen
        postDelayed({
            if (gen != pageLoadGeneration || humanCheckActive || userPaused) return@postDelayed
            if (playbackStarted && attempt > 0) {
                // Already reported playing — stop nudging to avoid mid-play scratch.
                return@postDelayed
            }
            injectRecaptchaUnlockHelper()
            injectFitPlaybackToScreen()
            webView?.evaluateJavascript(GatewayPlaybackJs.forceAutoplayScript()) { raw ->
                val status = raw?.trim()?.trim('"')?.lowercase().orEmpty()
                if (status == "playing") {
                    playbackStarted = true
                    return@evaluateJavascript
                }
                if (attempt < 6 && !userPaused) {
                    scheduleForceAutoplay(gen, attempt + 1)
                }
            }
        }, if (attempt == 0) 400L else 900L)
    }

    fun play() {
        userPaused = false
        playbackStarted = true
        nudgeVideoPlay()
    }

    fun pause() {
        userPaused = true
        playbackStarted = false
        forceAutoplayGeneration = -1
        webView?.evaluateJavascript(
            """
            (function(){
              function pauseIn(doc){
                try{
                  var vids=doc.querySelectorAll('video');
                  for(var i=0;i<vids.length;i++){try{vids[i].pause();}catch(e){}}
                }catch(e){}
                try{
                  var iframes=doc.querySelectorAll('iframe');
                  for(var i=0;i<iframes.length;i++){
                    try{
                      var d=iframes[i].contentDocument||iframes[i].contentWindow.document;
                      if(d)pauseIn(d);
                    }catch(e){}
                  }
                }catch(e){}
              }
              pauseIn(document);
            })();
            """.trimIndent(),
            null,
        )
        onPlaybackStateChanged(PlaybackState.PAUSED)
    }

    fun isPlaying(): Boolean = playbackStarted && !userPaused

    private fun nudgeVideoPlay() {
        if (userPaused) return
        webView?.evaluateJavascript(
            """
            (function(){
              function pickPrimary(doc){
                try{
                  var vids=doc.querySelectorAll('video');
                  if(!vids||!vids.length)return null;
                  var primary=null,best=-1;
                  for(var i=0;i<vids.length;i++){
                    var v=vids[i];
                    var score=(v.clientWidth||0)*(v.clientHeight||0);
                    if(!v.paused&&!v.ended)score+=1e9;
                    if(score>best){best=score;primary=v;}
                  }
                  for(var j=0;j<vids.length;j++){
                    if(vids[j]===primary){try{vids[j].muted=false;}catch(e){}}
                    else{try{vids[j].muted=true;vids[j].pause();}catch(e){}}
                  }
                  return primary;
                }catch(e){return null;}
              }
              function playIn(doc){
                var v=pickPrimary(doc);
                if(v){
                  try{
                    v.muted=false; v.playsInline=true; v.setAttribute('playsinline','');
                    if(v.paused && !v.ended){
                      var p=v.play();
                      if(p&&p.catch)p.catch(function(){});
                    }
                    return true;
                  }catch(e){}
                }
                var iframes=doc.querySelectorAll('iframe');
                for(var i=0;i<iframes.length;i++){
                  try{
                    var d=iframes[i].contentDocument||iframes[i].contentWindow.document;
                    if(d&&playIn(d))return true;
                  }catch(e){}
                }
                return false;
              }
              playIn(document);
            })();
            """.trimIndent(),
            null,
        )
    }

    fun stop() {
        webView?.stopLoading()
        webView?.loadUrl("about:blank")
    }

    fun setQuality(quality: StreamQuality, fromUser: Boolean = true) {
        if (!fromUser && userPickedQuality) return
        selectedQuality = quality
        if (fromUser) {
            userPickedQuality = true
        }
        qualityConfirmed = false
        qualityRetryGeneration++
        val mode = qualityModeFor(quality)
        Log.d(QUALITY_TAG, "setQuality $quality mode=$mode fromUser=$fromUser")
        try {
            ensurePlaybackApisInjected()
            applyQualityJs(mode, fromUser, scheduleRetries = fromUser)
            // Never re-call play() after quality inject — causes audio/video scratch.
        } catch (e: Exception) {
            Log.e(QUALITY_TAG, "setQuality failed: ${e.message}")
        }
    }

    private fun qualityModeFor(quality: StreamQuality): String = when (quality) {
        StreamQuality.AUTO -> "auto"
        else -> quality.height.toString()
    }

    private fun applyQualityAfterPageLoad() {
        // Startup: use AUTO (no maxHeight clamp). Forcing 360p via restrictions on DRM
        // live streams that only offer 540p caused Shaka 4012 hasAppRestrictions + audio-only.
        val mode = if (userPickedQuality) qualityModeFor(selectedQuality) else "auto"
        val fromUser = userPickedQuality
        Log.d(QUALITY_TAG, "applyQualityAfterPageLoad mode=$mode fromUser=$fromUser")
        applyQualityJs(mode, fromUser, scheduleRetries = true)
    }

    private fun applyQualityJs(mode: String, fromUser: Boolean, scheduleRetries: Boolean) {
        val gen = qualityRetryGeneration
        injectQuality(mode, fromUser)
        if (!scheduleRetries) return
        // Keep retries light — re-selecting every few hundred ms causes scratch/pause loops.
        val delays = if (fromUser) {
            listOf(800L, 2_500L)
        } else {
            listOf(1_500L)
        }
        delays.forEach { delayMs ->
            postDelayed({
                if (gen != qualityRetryGeneration) return@postDelayed
                if (qualityConfirmed) return@postDelayed
                if (!fromUser && userPickedQuality) return@postDelayed
                injectQuality(mode, fromUser)
            }, delayMs)
        }
    }

    fun setAudioLanguage(language: String) {
        val lang = normalizeAudioLanguage(language)
        val session = currentSession
        val w = webView
        if (session == null || w == null) {
            Log.w(TAG, "setAudioLanguage($lang) ignored — no session/webView")
            return
        }

        Log.d(TAG, "setAudioLanguage request=$lang (loaded=$lastLoadedAudioLanguage)")
        preferredAudioLanguage = lang
        audioLanguageConfirmed = false
        lastLoadedAudioLanguage = lang

        // Prefer in-page Shaka/hls.js switch — full reload often breaks playback / shows captcha.
        try {
            ensurePlaybackApisInjected()
            applyAudioLanguageJs(lang, scheduleRetries = true)
            // Do not force play() — language switch should not restart the decoder.
            postDelayed({
                if (!audioLanguageConfirmed && !userPaused) {
                    applyAudioLanguageJs(lang, scheduleRetries = false)
                }
            }, 2_000)
        } catch (e: Exception) {
            Log.e(TAG, "setAudioLanguage JS failed: ${e.message}")
        }
    }

    fun release() {
        cancelPendingRunnables()
        stopCaptchaPoll()
        stopClassifyPoll()
        pageFinishRunnable?.let { mainHandler.removeCallbacks(it) }
        pageFinishRunnable = null
        if (humanCheckActive) {
            humanCheckActive = false
            onHumanCheck(false)
        }
        // Persist cookies so reCAPTCHA only needs solving once per session/device.
        persistGatewayCookies()
        webView?.apply {
            stopLoading()
            // Do NOT clearCache / removeAllCookies — that forces captcha every open.
            clearHistory()
            removeJavascriptInterface("ShakaPlayerBridge")
            destroy()
        }
        webView = null
        playbackApisInjected = false
        captchaTokenSeen = false
        captchaReloadAttempted = false
    }

    fun getWebView(): WebView? = webView

    fun refreshSession(newSession: StreamSession) {
        currentSession = newSession
        playbackStarted = false
        playbackApisInjected = false
        preferredAudioLanguage = normalizeAudioLanguage(newSession.preferredAudioLanguage)
        lastLoadedAudioLanguage = preferredAudioLanguage
        val wv = webView ?: return
        val headers = buildLoadHeaders(newSession, preferredAudioLanguage)
        headers["User-Agent"]?.let { wv.settings.userAgentString = it }
        if (shouldUseWebView(newSession.mpdUrl)) {
            wv.loadUrl(newSession.mpdUrl, headers)
        }
    }

    private fun ensurePlaybackApisInjected() {
        val w = webView ?: return
        // Always re-arm capture — Shaka may load after first inject.
        injectPlayerCaptureHook()
        injectWidevineL3Fallback()
        if (playbackApisInjected) return
        playbackApisInjected = true
        w.evaluateJavascript(GatewayPlaybackJs.eaMaxOkoaQualityApiScript(), null)
        w.evaluateJavascript(GatewayPlaybackJs.eaMaxAudioLanguageApiScript(), null)
    }

    private fun injectQuality(mode: String, fromUser: Boolean) {
        val w = webView ?: return
        ensurePlaybackApisInjected()
        val safeMode = mode.filter { it.isDigit() || it == 'a' || it == 'u' || it == 't' || it == 'o' }
        w.evaluateJavascript(
            "try{window.__eaMaxPreferredAudioLang='${normalizeAudioLanguage(preferredAudioLanguage)}';" +
                "window.__eaMaxOkoaSetQuality&&window.__eaMaxOkoaSetQuality('$safeMode',${if (fromUser) "true" else "false"});}catch(e){}",
            null,
        )
    }

    private fun applyAudioLanguageJs(language: String, scheduleRetries: Boolean) {
        val w = webView ?: return
        val lang = normalizeAudioLanguage(language)
        if (audioLanguageConfirmed && lang == preferredAudioLanguage) return
        ensurePlaybackApisInjected()
        Log.d(TAG, "applyAudioLanguageJs lang=$lang scheduleRetries=$scheduleRetries")
        w.evaluateJavascript(GatewayPlaybackJs.eaMaxAudioLanguageApiScript(), null)
        w.evaluateJavascript(
            "(function(){" +
                "try{" +
                "window.__eaMaxPreferredAudioLang='$lang';" +
                "if(window.__eaMaxSetAudioLanguage){window.__eaMaxSetAudioLanguage('$lang');}" +
                "}catch(e){}" +
                "})();",
            null,
        )
        if (scheduleRetries) {
            // Fewer retries — aggressive re-apply was causing scratch + double audio.
            listOf(1500L, 4500L).forEach { delayMs ->
                postDelayed({
                    if (audioLanguageConfirmed) return@postDelayed
                    applyAudioLanguageJs(lang, scheduleRetries = false)
                }, delayMs)
            }
        }
    }

    private fun postDelayed(block: () -> Unit, delayMs: Long) {
        val r = Runnable { block() }
        pendingRunnables.add(r)
        mainHandler.postDelayed(r, delayMs)
    }

    private fun cancelPendingRunnables() {
        pendingRunnables.forEach { mainHandler.removeCallbacks(it) }
        pendingRunnables.clear()
    }

    private fun normalizeAudioLanguage(raw: String): String {
        val v = raw.trim().lowercase()
        return if (v == "en" || v.startsWith("en-") || v == "eng") "en" else "sw"
    }
}

class WebViewJsInterface(
    private val onPlaybackStateChanged: (PlaybackState) -> Unit,
    private val onError: (String) -> Unit,
    private val onAudioProbe: (wanted: String, applied: Boolean) -> Unit = { _, _ -> },
    private val onQualityProbe: (wanted: String, maxH: Int, activeH: Int, applied: Boolean) -> Unit =
        { _, _, _, _ -> },
) {
    @android.webkit.JavascriptInterface
    fun onPlaybackStarted() { onPlaybackStateChanged(PlaybackState.PLAYING) }

    @android.webkit.JavascriptInterface
    fun onPlaybackPaused() { onPlaybackStateChanged(PlaybackState.PAUSED) }

    @android.webkit.JavascriptInterface
    fun onPlaybackTick(seconds: Int) {}

    @android.webkit.JavascriptInterface
    fun onPlaybackError(errorMessage: String) {
        onError("WebView Playback Error: $errorMessage")
    }

    @android.webkit.JavascriptInterface
    fun onPlaybackEnded() { onPlaybackStateChanged(PlaybackState.ENDED) }

    @android.webkit.JavascriptInterface
    fun onAudioLanguageProbe(json: String) {
        Log.d("EaMaxAudio", "probe: $json")
        try {
            val wanted = Regex(""""wanted"\s*:\s*"([^"]+)"""").find(json)?.groupValues?.get(1) ?: ""
            val applied = """"applied"\s*:\s*true""".toRegex().containsMatchIn(json)
            onAudioProbe(wanted, applied)
        } catch (_: Exception) { }
    }

    @android.webkit.JavascriptInterface
    fun onQualityProbe(json: String) {
        Log.d("EaMaxQuality", "probe: $json")
        try {
            fun num(key: String) =
                Regex(""""$key"\s*:\s*(\d+)""").find(json)?.groupValues?.get(1)?.toIntOrNull() ?: 0
            val wanted = Regex(""""wanted"\s*:\s*"([^"]+)"""").find(json)?.groupValues?.get(1) ?: ""
            val applied = """"applied"\s*:\s*true""".toRegex().containsMatchIn(json)
            onQualityProbe(wanted, num("maxH"), num("activeH"), applied)
        } catch (_: Exception) { }
    }
}
