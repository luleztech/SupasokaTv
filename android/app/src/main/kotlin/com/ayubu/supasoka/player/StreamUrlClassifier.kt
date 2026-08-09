package com.ayubu.supasoka.player

/**
 * Shared gateway / direct-stream URL rules (aligned with Flutter).
 */
object StreamUrlClassifier {

    fun needsWebPlayer(url: String): Boolean {
        val u = url.trim()
        if (u.isEmpty()) return false
        if (hasObviousM3u8(u) || hasObviousMpd(u) || hasObviousTs(u)) return false
        if (isLikelyIptvLiveUrl(u)) return false
        return isPhpLikeUrl(u) || isLikelyGatewayUrl(u)
    }

    fun hasObviousM3u8(url: String) = url.lowercase().contains(".m3u8")

    fun hasObviousMpd(url: String) = url.lowercase().contains(".mpd")

    fun hasObviousTs(url: String): Boolean {
        val l = url.lowercase()
        return l.contains(".ts?") || l.endsWith(".ts") || l.contains(".mp4?") || l.endsWith(".mp4")
    }

    fun hasObviousProgressiveExtension(url: String): Boolean {
        val u = url.lowercase()
        return listOf(".mp4", ".m4v", ".webm", ".mkv", ".mov", ".ts").any { u.contains(it) }
    }

    fun isPhpLikeUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        return """\.php($|[/?#])""".toRegex(RegexOption.IGNORE_CASE).containsMatchIn(url)
    }

    fun isLikelyGatewayUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        val u = url.lowercase()
        return """\.(php|asp|aspx|cgi|jsp)(\?|#|$|/)""".toRegex(RegexOption.IGNORE_CASE).containsMatchIn(u) ||
            u.contains("/embed/") ||
            u.contains("/gateway/") ||
            u.contains("/stream/") ||
            u.contains("/play/") ||
            u.contains("/player/")
    }

    fun isRelayStyleUrl(url: String): Boolean {
        val u = url.lowercase()
        return "/relay/stream" in u || "/relay/m3u8" in u || "/api/relay/" in u
    }

    fun isLikelyIptvLiveUrl(url: String): Boolean {
        val base = url.split("#").first().lowercase()
        if (hasObviousM3u8(url) || hasObviousMpd(url) || hasObviousTs(url)) return false
        if ("""^https?://[^/]+:\d{2,5}/(live|stream|play|hls|iptv|channel|ch)/""".toRegex().containsMatchIn(base)) {
            return true
        }
        if ("""^https?://[^/]+:\d{2,5}/[^/]+/[^/]+/[^/?#]+$""".toRegex().containsMatchIn(base)) return true
        if ("""^https?://[^/]+/(live|stream|play|hls|iptv|channel|ch)/[^/?#]+""".toRegex().containsMatchIn(base)) {
            return true
        }
        return false
    }
}
