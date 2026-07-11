package com.ayubu.supasoka.player

import android.content.Context
import android.webkit.WebView
import androidx.media3.common.Tracks
import com.ayubu.supasoka.domain.model.PlaybackState
import com.ayubu.supasoka.domain.model.PlayerMode
import com.ayubu.supasoka.domain.model.StreamQuality
import com.ayubu.supasoka.domain.model.StreamSession
import android.util.Log

/**
 * EaMax player facade — based on NixSwahili reference player.
 * Routes direct manifests to ExoPlayer; PHP / gateway pages to WebView.
 */
class PlayerManager(
    private val context: Context,
    private val onStateChanged: (PlaybackState) -> Unit = {},
    private val onError: (String) -> Unit = {},
    private val onTracksAvailable: (Tracks) -> Unit = {},
) {
    private var engine: ExoPlayerEngine? = null
    private var webViewEngine: WebViewEngine? = null
    private var currentSession: StreamSession? = null
    private var isInitialized = false

    private enum class ActiveEngine { NONE, EXO, WEBVIEW }
    private var activeEngine = ActiveEngine.NONE

    companion object {
        private const val TAG = "PlayerManager"
    }

    fun isExoPlayback(): Boolean = activeEngine == ActiveEngine.EXO
    fun isWebViewPlayback(): Boolean = activeEngine == ActiveEngine.WEBVIEW

    fun initialize(streamSession: StreamSession) {
        Log.d(TAG, "Initializing player: ${streamSession.sessionId} url=${streamSession.mpdUrl.take(80)}")
        if (isInitialized) release()

        val gatewayCandidate = streamSession.playerMode == PlayerMode.WEB ||
            StreamUrlClassifier.needsWebPlayer(streamSession.mpdUrl)

        if (gatewayCandidate) {
            val resolved = GatewayPlaybackResolver.resolve(streamSession)
            if (resolved != null) {
                val session = applyResolvedSession(streamSession, resolved)
                currentSession = session
                startExoEngine(session)
                isInitialized = true
                return
            }
            Log.d(TAG, "Gateway probe failed — WebView fallback")
            currentSession = streamSession
            startWebViewEngine(streamSession)
            isInitialized = true
            return
        }

        currentSession = streamSession
        startExoEngine(streamSession)
        isInitialized = true
    }

    private fun applyResolvedSession(
        base: StreamSession,
        resolved: GatewayPlaybackResolver.Resolved,
    ): StreamSession {
        val drmType = resolved.drmType ?: base.drmType
        return base.copy(
            mpdUrl = resolved.streamUrl,
            licenseUrl = resolved.licenseUrl.ifBlank { base.licenseUrl },
            token = resolved.authToken.ifBlank { base.token },
            headers = resolved.headers,
            drmType = drmType,
            playerMode = PlayerMode.EXO,
        )
    }

    private fun startExoEngine(streamSession: StreamSession) {
        Log.d(TAG, "Engine → ExoPlayer")
        engine = ExoPlayerEngine(
            context = context,
            onPlaybackStateChanged = { state ->
                Log.d(TAG, "Exo state: $state")
                onStateChanged(state)
            },
            onError = { error ->
                Log.e(TAG, "Exo error: $error")
                onError(error)
            },
            onTracksChangedCallback = { tracks -> onTracksAvailable(tracks) },
        )
        engine?.initialize(streamSession)
        activeEngine = ActiveEngine.EXO
    }

    private fun startWebViewEngine(streamSession: StreamSession) {
        Log.d(TAG, "Engine → WebView (gateway page)")
        webViewEngine = WebViewEngine(
            context = context,
            onPlaybackStateChanged = { state ->
                Log.d(TAG, "WebView state: $state")
                onStateChanged(state)
            },
            onError = { err ->
                Log.e(TAG, "WebView error: $err")
                onError(err)
            },
        )
        webViewEngine?.initialize(streamSession)
        activeEngine = ActiveEngine.WEBVIEW
    }

    fun play() {
        if (!isInitialized) return
        when (activeEngine) {
            ActiveEngine.WEBVIEW -> webViewEngine?.play()
            ActiveEngine.EXO -> engine?.play()
            ActiveEngine.NONE -> { }
        }
    }

    fun pause() {
        if (!isInitialized) return
        when (activeEngine) {
            ActiveEngine.WEBVIEW -> webViewEngine?.pause()
            ActiveEngine.EXO -> engine?.pause()
            ActiveEngine.NONE -> { }
        }
    }

    fun stop() {
        if (!isInitialized) return
        when (activeEngine) {
            ActiveEngine.WEBVIEW -> webViewEngine?.stop()
            ActiveEngine.EXO -> engine?.stop()
            ActiveEngine.NONE -> { }
        }
    }

    fun release() {
        Log.d(TAG, "Releasing player")
        engine?.release()
        engine = null
        webViewEngine?.release()
        webViewEngine = null
        isInitialized = false
        activeEngine = ActiveEngine.NONE
        currentSession = null
    }

    fun seekTo(positionMs: Long) {
        if (activeEngine != ActiveEngine.EXO) return
        engine?.getPlayer()?.seekTo(positionMs)
    }

    fun setQuality(quality: StreamQuality, fromUser: Boolean = true) {
        when (activeEngine) {
            ActiveEngine.WEBVIEW -> webViewEngine?.setQuality(quality, fromUser)
            ActiveEngine.EXO -> engine?.setQuality(quality)
            ActiveEngine.NONE -> { }
        }
        Log.d(TAG, "Quality → $quality (fromUser=$fromUser, engine=$activeEngine)")
    }

    fun setAudioLanguage(language: String) {
        when (activeEngine) {
            ActiveEngine.WEBVIEW -> webViewEngine?.setAudioLanguage(language)
            ActiveEngine.EXO -> engine?.setAudioLanguage(language)
            ActiveEngine.NONE -> { }
        }
        Log.d(TAG, "Audio language → $language (engine=$activeEngine)")
    }

    fun setTrack(group: Tracks.Group, trackIndex: Int) {
        engine?.setTrack(group, trackIndex)
    }

    fun getCurrentPosition(): Long = engine?.getCurrentPosition() ?: 0L
    fun getDuration(): Long = engine?.getDuration() ?: 0L

    fun isPlaying(): Boolean = when (activeEngine) {
        ActiveEngine.WEBVIEW -> webViewEngine?.isPlaying() == true
        ActiveEngine.EXO -> engine?.isPlaying() == true
        ActiveEngine.NONE -> false
    }

    fun getAvailableTracks(): Tracks = engine?.getAvailableTracks() ?: Tracks.EMPTY
    fun getExoPlayer() = engine?.getPlayer()
    fun getWebView(): WebView? = webViewEngine?.getWebView()

    fun refreshSession(newSession: StreamSession) {
        currentSession = newSession
        when (activeEngine) {
            ActiveEngine.WEBVIEW -> webViewEngine?.refreshSession(newSession)
            ActiveEngine.EXO -> engine?.refreshSession(newSession)
            ActiveEngine.NONE -> { }
        }
    }

    fun isInitialized(): Boolean = isInitialized
    fun getCurrentSession(): StreamSession? = currentSession
}
