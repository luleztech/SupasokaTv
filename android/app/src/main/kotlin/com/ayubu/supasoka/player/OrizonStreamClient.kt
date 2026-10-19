package com.ayubu.supasoka.player

import android.net.Uri
import android.util.Log
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/**
 * Stream HTTP stack recovered from Orizon TV 1.7.1 (`streamOkHttpClient` + OkHttpDataSource).
 */
object OrizonStreamClient {
    private const val TAG = "OrizonHttp"
    const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

    private const val CONNECT_TIMEOUT_SEC = 20L
    private const val READ_TIMEOUT_SEC = 30L
    private const val WRITE_TIMEOUT_SEC = 20L

    val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(CONNECT_TIMEOUT_SEC, TimeUnit.SECONDS)
            .readTimeout(READ_TIMEOUT_SEC, TimeUnit.SECONDS)
            .writeTimeout(WRITE_TIMEOUT_SEC, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .followRedirects(true)
            .followSslRedirects(true)
            .addInterceptor { chain ->
                HlsPlaylistStitcher.maybeRewrite(chain.proceed(chain.request()))
            }
            .addNetworkInterceptor { chain ->
                val request = chain.request()
                val response = chain.proceed(request)
                val diagnosticHeaders = listOf(
                    "Server",
                    "Via",
                    "X-Cache",
                    "Content-Type",
                    "WWW-Authenticate",
                    "X-Amz-Cf-Pop",
                ).mapNotNull { name ->
                    response.header(name)?.let { value -> "$name=$value" }
                }.joinToString(" ")
                Log.i(
                    TAG,
                    "${request.method} ${request.url.scheme}://${request.url.host} " +
                        "-> ${response.code} " +
                        "refererHost=${headerHost(request.header("Referer"))} " +
                        "originHost=${headerHost(request.header("Origin"))} " +
                        diagnosticHeaders,
                )
                response
            }
            .build()
    }

    fun dataSourceFactory(headers: Map<String, String>): HttpDataSource.Factory {
        val userAgent = headers.entries
            .firstOrNull { it.key.equals("User-Agent", ignoreCase = true) }
            ?.value
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: USER_AGENT
        return OkHttpDataSource.Factory(okHttpClient)
            .setUserAgent(userAgent)
            .setDefaultRequestProperties(headers)
    }

    private fun headerHost(raw: String?): String {
        if (raw.isNullOrBlank()) return "<missing>"
        val uri = runCatching { Uri.parse(raw) }.getOrNull() ?: return "<invalid>"
        val scheme = uri.scheme ?: return "<invalid>"
        val host = uri.host ?: return "<invalid>"
        return "$scheme://$host"
    }
}
