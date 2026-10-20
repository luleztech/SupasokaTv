package com.ayubu.supasoka.player

import android.net.Uri
import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import java.util.concurrent.TimeUnit

/**
 * Live bridges often restart `#EXT-X-MEDIA-SEQUENCE` when they rotate CDN hosts.
 * ExoPlayer treats that jump as [androidx.media3.exoplayer.hls.playlist.HlsPlaylistTracker.PlaylistResetException]
 * and tears the decoder down. Rewriting the sequence so it keeps increasing lets the
 * same player continue across the discontinuity.
 */
object HlsPlaylistStitcher {
    private const val TAG = "HlsPlaylistStitcher"
    private const val MAX_PLAYLIST_CHARS = 1_500_000

    private val mediaSequencePattern = Regex("""#EXT-X-MEDIA-SEQUENCE:(\d+)""")
    private val discontinuitySequencePattern = Regex("""#EXT-X-DISCONTINUITY-SEQUENCE:(\d+)""")
    private val extInfPattern = Regex("""#EXTINF:""")

    private data class Snapshot(
        val serverSequence: Long,
        val publishedSequence: Long,
        val segmentCount: Int,
        val discontinuitySequence: Int,
    )

    private val lock = Any()
    private val lastByPlaylist = HashMap<String, Snapshot>()
    private val segmentUrlPattern = Regex("""(?m)^https?://\S+""")

    @Volatile
    private var playlistRequest: Request? = null

    private val fetchClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(12, TimeUnit.SECONDS)
            .followRedirects(true)
            .retryOnConnectionFailure(true)
            .build()
    }

    fun reset() {
        synchronized(lock) {
            lastByPlaylist.clear()
        }
    }

    fun maybeRewrite(response: Response): Response {
        val body = response.body ?: return response
        val contentLength = body.contentLength()
        if (contentLength > MAX_PLAYLIST_CHARS) return response
        val prefix = try {
            val peeked = body.source().peek()
            peeked.request(48)
            val size = minOf(peeked.buffer.size, 48)
            if (size <= 0L) return response
            peeked.buffer.clone().readUtf8(size)
        } catch (_: Exception) {
            return response
        }
        if (!prefix.contains("#EXTM3U")) return response

        playlistRequest = response.request
        val mediaType = body.contentType()
        val raw = try {
            body.string()
        } catch (_: Exception) {
            return response
        }
        val rewritten = rewrite(
            response.request.url.toString(),
            dropUnreadyLiveEdge(normalizePlaylist(raw)),
        )
        val bytes = rewritten.toByteArray(Charsets.UTF_8)
        return response.newBuilder()
            .body(bytes.toResponseBody(mediaType))
            .header("Content-Length", bytes.size.toString())
            .removeHeader("Content-Encoding")
            .removeHeader("Transfer-Encoding")
            .build()
    }

    /**
     * The CDN host named in the playlist often answers 404 for the exact URL
     * ExoPlayer opens (nginx HTML). A freshly listed file on that same bridge
     * still plays, so hand that file back instead of failing the channel.
     */
    fun replacementForMissingSegment(failed: Request): Response? {
        val path = failed.url.encodedPath.lowercase()
        if (path.endsWith(".m3u8") || path.endsWith(".m3u")) return null
        val original = playlistRequest ?: return null
        repeat(3) { attempt ->
            val playlistUrl = cacheBust(original.url.toString(), attempt)
            val playlistText = getText(playlistUrl, original) ?: return@repeat
            val urls = segmentUrlPattern.findAll(dropUnreadyLiveEdge(normalizePlaylist(playlistText)))
                .map { it.value.trim() }
                .toList()
            for (url in urls.asReversed().take(4)) {
                val segment = getResponse(url, original) ?: continue
                if (segment.isSuccessful && (segment.body?.contentLength() ?: 1L) != 0L) {
                    Log.i(TAG, "replaced 404 segment with a live file from the refreshed playlist")
                    return segment.newBuilder().request(failed).build()
                }
                segment.close()
            }
        }
        return null
    }

    private fun normalizePlaylist(raw: String): String {
        return raw.replace("\r\n", "\n").replace('\r', '\n')
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .joinToString("\n") + "\n"
    }

    private fun cacheBust(url: String, attempt: Int): String {
        val joiner = if (url.contains("?")) "&" else "?"
        return "$url${joiner}_r=$attempt${System.currentTimeMillis()}"
    }

    private fun getText(url: String, template: Request): String? {
        val response = getResponse(url, template) ?: return null
        return try {
            if (!response.isSuccessful) {
                response.close()
                null
            } else {
                response.body?.string()
            }
        } catch (_: Exception) {
            response.close()
            null
        }
    }

    private fun getResponse(url: String, template: Request): Response? {
        val builder = Request.Builder().url(url).get()
        for (name in listOf("User-Agent", "Accept", "Accept-Language", "X-Requested-With")) {
            template.header(name)?.let { builder.header(name, it) }
        }
        return try {
            fetchClient.newCall(builder.build()).execute()
        } catch (_: Exception) {
            null
        }
    }

    /**
     * The last live segment is often listed before the CDN can serve it, so the
     * first read is a 404 and playback stops. Drop that one edge file when older
     * segments are still in the playlist. Finished playlists are left alone.
     */
    internal fun dropUnreadyLiveEdge(playlist: String): String {
        if (!playlist.contains("#EXTM3U") || playlist.contains("#EXT-X-ENDLIST")) return playlist
        val matches = extInfPattern.findAll(playlist).toList()
        if (matches.size < 4) return playlist
        return playlist.substring(0, matches.last().range.first).trimEnd() + "\n"
    }

    internal fun rewrite(rawUrl: String, playlist: String): String {
        if (playlist.length > MAX_PLAYLIST_CHARS) return playlist
        if (!playlist.contains("#EXT-X-MEDIA-SEQUENCE:")) return playlist
        val sequenceMatch = mediaSequencePattern.find(playlist) ?: return playlist
        val sequence = sequenceMatch.groupValues[1].toLongOrNull() ?: return playlist
        val segmentCount = extInfPattern.findAll(playlist).count()
        if (segmentCount <= 0) return playlist
        val discontinuityMatch = discontinuitySequencePattern.find(playlist)
        val discontinuity = discontinuityMatch?.groupValues?.get(1)?.toIntOrNull() ?: 0
        val key = playlistKey(rawUrl)

        synchronized(lock) {
            val previous = lastByPlaylist[key]
            if (previous == null) {
                lastByPlaylist[key] = Snapshot(sequence, sequence, segmentCount, discontinuity)
                return playlist
            }
            val rawOverlaps = sequence + segmentCount >= previous.publishedSequence &&
                sequence >= previous.publishedSequence - previous.segmentCount
            if (rawOverlaps) {
                if (sequence >= previous.publishedSequence) {
                    lastByPlaylist[key] = Snapshot(
                        serverSequence = sequence,
                        publishedSequence = sequence,
                        segmentCount = segmentCount,
                        discontinuitySequence = previous.discontinuitySequence,
                    )
                }
                return playlist
            }
            val offset = previous.publishedSequence - previous.serverSequence
            val projected = sequence + offset
            val overlaps = projected + segmentCount >= previous.publishedSequence
            if (overlaps) {
                if (sequence >= previous.serverSequence) {
                    lastByPlaylist[key] = previous.copy(
                        serverSequence = sequence,
                        publishedSequence = projected,
                        segmentCount = segmentCount,
                    )
                }
                if (projected == sequence) return playlist
                return replaceMediaSequence(playlist, sequenceMatch.value, projected)
            }
            val nextSequence = previous.publishedSequence + previous.segmentCount
            val nextDiscontinuity = previous.discontinuitySequence + 1
            var updated = replaceMediaSequence(playlist, sequenceMatch.value, nextSequence)
            val rewrittenDisc = discontinuitySequencePattern.find(updated)
            updated = if (rewrittenDisc != null) {
                updated.replace(
                    rewrittenDisc.value,
                    "#EXT-X-DISCONTINUITY-SEQUENCE:$nextDiscontinuity",
                )
            } else {
                updated.replace(
                    "#EXT-X-MEDIA-SEQUENCE:$nextSequence",
                    "#EXT-X-DISCONTINUITY-SEQUENCE:$nextDiscontinuity\n#EXT-X-MEDIA-SEQUENCE:$nextSequence",
                )
            }
            val firstSegment = updated.indexOf("#EXTINF:")
            if (firstSegment >= 0) {
                val before = updated.substring(0, firstSegment).trimEnd()
                if (!before.endsWith("#EXT-X-DISCONTINUITY")) {
                    updated = updated.replaceFirst("#EXTINF:", "#EXT-X-DISCONTINUITY\n#EXTINF:")
                }
            }
            lastByPlaylist[key] = Snapshot(
                serverSequence = sequence,
                publishedSequence = nextSequence,
                segmentCount = segmentCount,
                discontinuitySequence = nextDiscontinuity,
            )
            Log.i(
                TAG,
                "stitched media sequence $sequence -> $nextSequence segments=$segmentCount",
            )
            return updated
        }
    }

    private fun replaceMediaSequence(playlist: String, currentTag: String, sequence: Long): String {
        return playlist.replace(currentTag, "#EXT-X-MEDIA-SEQUENCE:$sequence")
    }

    private fun playlistKey(rawUrl: String): String {
        val uri = Uri.parse(rawUrl)
        val scheme = uri.scheme ?: "http"
        val host = uri.host ?: rawUrl
        val port = if (uri.port > 0) ":${uri.port}" else ""
        return "$scheme://$host$port${uri.path.orEmpty()}"
    }
}
