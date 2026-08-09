package com.ayubu.supasoka.player

import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.ProgressBar
import androidx.annotation.OptIn
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import com.ayubu.supasoka.domain.model.PlaybackState

/**
 * Loading and buffering indicators only — does not modify native Media3 controller widgets.
 * Short rebuffers are ignored so the UI does not flicker and disturb watching.
 */
@OptIn(UnstableApi::class)
class SupasokaPlayerOverlay(
    private val loadingOverlay: View,
    private val bufferingBar: ProgressBar,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var attachedPlayer: Player? = null
    private var webViewMode = false
    private var playbackState = PlaybackState.IDLE
    private var firstFrameShown = false

    private val showBufferingRunnable = Runnable {
        if (playbackState == PlaybackState.BUFFERING && firstFrameShown) {
            loadingOverlay.visibility = View.GONE
            bufferingBar.visibility = View.VISIBLE
        }
    }

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            syncFromPlayer(attachedPlayer)
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            syncFromPlayer(attachedPlayer)
        }

        override fun onRenderedFirstFrame() {
            markFirstFrameReady()
        }
    }

    fun attachExoPlayer(player: Player) {
        detach()
        webViewMode = false
        attachedPlayer = player
        player.addListener(playerListener)
        syncFromPlayer(player)
    }

    /**
     * @param alreadyPlaying When WebView is already decoding (e.g. revert after failed Exo promotion),
     *   keep the screen clean — never re-show the full-screen spinner.
     */
    fun attachWebViewMode(alreadyPlaying: Boolean = false) {
        detach()
        webViewMode = true
        attachedPlayer = null
        if (alreadyPlaying || playbackState == PlaybackState.PLAYING) {
            markFirstFrameReady()
        } else {
            firstFrameShown = false
            loadingOverlay.visibility = View.VISIBLE
            bufferingBar.visibility = View.GONE
        }
    }

    /** Force-clear loading/buffering so reCAPTCHA stays tappable. */
    fun clearForHumanCheck() {
        firstFrameShown = false
        mainHandler.removeCallbacks(showBufferingRunnable)
        loadingOverlay.visibility = View.GONE
        bufferingBar.visibility = View.GONE
    }

    fun detach() {
        attachedPlayer?.removeListener(playerListener)
        attachedPlayer = null
        mainHandler.removeCallbacks(showBufferingRunnable)
    }

    fun onEngineStateChanged(state: PlaybackState) {
        playbackState = state
        when (state) {
            PlaybackState.PLAYING -> {
                markFirstFrameReady()
            }
            PlaybackState.BUFFERING -> {
                if (firstFrameShown) {
                    // Debounce: ignore brief rebuffers so the bar does not flash.
                    scheduleBufferingIndicator()
                } else if (webViewMode) {
                    bufferingBar.visibility = View.VISIBLE
                } else {
                    showBufferingIndicator()
                }
            }
            PlaybackState.READY -> {
                mainHandler.removeCallbacks(showBufferingRunnable)
                bufferingBar.visibility = View.GONE
                if (!webViewMode && attachedPlayer != null) {
                    syncFromPlayer(attachedPlayer)
                }
            }
            PlaybackState.PAUSED -> {
                mainHandler.removeCallbacks(showBufferingRunnable)
                bufferingBar.visibility = View.GONE
            }
            else -> { }
        }
    }

    /** Gateway → Exo handoff: keep video visible without flashing the bar. */
    fun markStreamHandoff() {
        firstFrameShown = true
        mainHandler.removeCallbacks(showBufferingRunnable)
        loadingOverlay.visibility = View.GONE
        bufferingBar.visibility = View.GONE
    }

    fun resetForNewStream() {
        firstFrameShown = false
        mainHandler.removeCallbacks(showBufferingRunnable)
        loadingOverlay.visibility = View.VISIBLE
        bufferingBar.visibility = View.GONE
    }

    fun dismissLoadingForWebView() {
        markFirstFrameReady()
    }

    private fun markFirstFrameReady() {
        firstFrameShown = true
        mainHandler.removeCallbacks(showBufferingRunnable)
        loadingOverlay.visibility = View.GONE
        bufferingBar.visibility = View.GONE
    }

    private fun scheduleBufferingIndicator() {
        mainHandler.removeCallbacks(showBufferingRunnable)
        mainHandler.postDelayed(showBufferingRunnable, BUFFERING_UI_DELAY_MS)
    }

    private fun showBufferingIndicator() {
        if (firstFrameShown || playbackState == PlaybackState.PLAYING || attachedPlayer?.isPlaying == true) {
            scheduleBufferingIndicator()
        } else if (webViewMode) {
            bufferingBar.visibility = View.VISIBLE
        } else {
            bufferingBar.visibility = View.GONE
            loadingOverlay.visibility = View.VISIBLE
        }
    }

    /** Sync overlay when listener attaches after Exo already prepared (avoids spinner over playing video). */
    private fun syncFromPlayer(player: Player?) {
        if (webViewMode || player == null) return

        val ready = player.playbackState == Player.STATE_READY ||
            player.playbackState == Player.STATE_BUFFERING ||
            player.playbackState == Player.STATE_ENDED
        val playing = player.isPlaying

        if (ready || playing) {
            firstFrameShown = true
            loadingOverlay.visibility = View.GONE
        }

        if (player.playbackState == Player.STATE_BUFFERING && firstFrameShown) {
            scheduleBufferingIndicator()
        } else {
            mainHandler.removeCallbacks(showBufferingRunnable)
            bufferingBar.visibility = View.GONE
        }
    }

    companion object {
        private const val BUFFERING_UI_DELAY_MS = 900L
    }
}
