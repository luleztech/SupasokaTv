package com.ayubu.supasoka.player

import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.ProgressBar
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView
import com.ayubu.supasoka.R
import com.ayubu.supasoka.domain.model.PlaybackState

/**
 * Polishes native player chrome: LIVE badge for IPTV, clean mm:ss times for VOD,
 * buffering strip, and loading overlay — hides Media3's noisy default time labels on live streams.
 */
@OptIn(UnstableApi::class)
class SupasokaPlayerOverlay(
    private val playerView: PlayerView,
    private val loadingOverlay: View,
    private val bufferingBar: ProgressBar,
    private val liveBadge: TextView,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var attachedPlayer: Player? = null
    private var webViewMode = false
    private var playbackState = PlaybackState.IDLE
    private var firstFrameShown = false

    private val positionView: TextView? =
        playerView.findViewById(R.id.exo_position)
    private val durationView: TextView? =
        playerView.findViewById(R.id.exo_duration)
    private val inlineLiveBadge: TextView? =
        playerView.findViewById(R.id.supasoka_live_badge_inline)
    private val progressBar: View? =
        playerView.findViewById(R.id.exo_progress)

    private val tickRunnable = object : Runnable {
        override fun run() {
            refreshTimeLabels()
            mainHandler.postDelayed(this, TICK_MS)
        }
    }

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            refreshBufferingUi()
            if (state == Player.STATE_READY && !firstFrameShown) {
                firstFrameShown = true
                loadingOverlay.visibility = View.GONE
            }
            refreshTimeLabels()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            refreshBufferingUi()
        }

        override fun onRenderedFirstFrame() {
            firstFrameShown = true
            loadingOverlay.visibility = View.GONE
        }
    }

    fun attachExoPlayer(player: Player) {
        detach()
        webViewMode = false
        attachedPlayer = player
        player.addListener(playerListener)
        mainHandler.post(tickRunnable)
        refreshBufferingUi()
        refreshTimeLabels()
    }

    fun attachWebViewMode() {
        detach()
        webViewMode = true
        attachedPlayer = null
        loadingOverlay.visibility = View.VISIBLE
        liveBadge.visibility = View.VISIBLE
        hideVodControls()
        inlineLiveBadge?.visibility = View.VISIBLE
        progressBar?.visibility = View.GONE
    }

    fun detach() {
        attachedPlayer?.removeListener(playerListener)
        attachedPlayer = null
        mainHandler.removeCallbacks(tickRunnable)
    }

    fun onEngineStateChanged(state: PlaybackState) {
        playbackState = state
        when (state) {
            PlaybackState.PLAYING -> {
                if (webViewMode) {
                    firstFrameShown = true
                    loadingOverlay.visibility = View.GONE
                    liveBadge.visibility = View.VISIBLE
                }
                bufferingBar.visibility = View.GONE
            }
            PlaybackState.BUFFERING -> {
                if (firstFrameShown || webViewMode) {
                    bufferingBar.visibility = View.VISIBLE
                } else {
                    loadingOverlay.visibility = View.VISIBLE
                }
            }
            PlaybackState.READY -> {
                bufferingBar.visibility = View.GONE
                if (!webViewMode && attachedPlayer != null) {
                    refreshTimeLabels()
                }
            }
            PlaybackState.PAUSED -> bufferingBar.visibility = View.GONE
            else -> { }
        }
        refreshBufferingUi()
    }

    fun resetForNewStream() {
        firstFrameShown = false
        loadingOverlay.visibility = View.VISIBLE
        bufferingBar.visibility = View.GONE
        liveBadge.visibility = View.GONE
    }

    private fun refreshBufferingUi() {
        if (webViewMode) return
        val player = attachedPlayer ?: return
        val buffering = player.playbackState == Player.STATE_BUFFERING
        if (buffering && firstFrameShown) {
            bufferingBar.visibility = View.VISIBLE
        } else if (player.playbackState == Player.STATE_READY ||
            player.playbackState == Player.STATE_ENDED
        ) {
            bufferingBar.visibility = View.GONE
        }
    }

    private fun refreshTimeLabels() {
        if (webViewMode) return
        val player = attachedPlayer ?: return

        if (isEffectivelyLive(player)) {
            hideVodControls()
            liveBadge.visibility = View.VISIBLE
            inlineLiveBadge?.visibility = View.VISIBLE
            return
        }

        liveBadge.visibility = View.GONE
        inlineLiveBadge?.visibility = View.GONE
        progressBar?.visibility = View.VISIBLE

        val pos = player.currentPosition
        val dur = player.duration
        if (!isValidTimeMs(pos) || !isValidTimeMs(dur)) {
            positionView?.visibility = View.GONE
            durationView?.visibility = View.GONE
            return
        }

        positionView?.apply {
            visibility = View.VISIBLE
            text = formatMs(pos)
        }
        durationView?.apply {
            visibility = View.VISIBLE
            text = formatMs(dur)
        }
    }

    private fun hideVodControls() {
        positionView?.visibility = View.GONE
        durationView?.visibility = View.GONE
        progressBar?.visibility = View.GONE
    }

    companion object {
        private const val TICK_MS = 500L
        /** Live IPTV often reports multi-hour DVR windows — treat as live, not scrubbable VOD. */
        private const val MAX_VOD_DURATION_MS = 4L * 60 * 60 * 1000

        fun isEffectivelyLive(player: Player): Boolean {
            if (player.isCurrentMediaItemLive) return true
            val dur = player.duration
            if (dur == C.TIME_UNSET || dur <= 0) return true
            if (dur > MAX_VOD_DURATION_MS) return true
            return false
        }

        fun isValidTimeMs(ms: Long): Boolean {
            return ms != C.TIME_UNSET && ms >= 0 && ms <= MAX_VOD_DURATION_MS
        }

        /** Clean wall-clock style: 0:42 or 1:05:30 — never milliseconds or huge numbers. */
        fun formatMs(ms: Long): String {
            if (!isValidTimeMs(ms)) return ""
            val totalSec = (ms / 1000).coerceAtMost(99 * 3600L + 59 * 60 + 59)
            val h = totalSec / 3600
            val m = (totalSec % 3600) / 60
            val s = totalSec % 60
            return if (h > 0) {
                String.format("%d:%02d:%02d", h, m, s)
            } else {
                String.format("%d:%02d", m, s)
            }
        }
    }
}
