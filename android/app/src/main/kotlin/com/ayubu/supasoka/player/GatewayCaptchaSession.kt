package com.ayubu.supasoka.player

import android.content.Context

/**
 * Remembers that a gateway host completed human verification on this device.
 * Cookies do the real work; this flag only helps logging / future fast-paths.
 */
object GatewayCaptchaSession {
    private const val PREFS = "supasoka_gateway_captcha"
    private const val KEY_PREFIX = "solved_"

    fun markSolved(context: Context, host: String) {
        val h = host.trim().lowercase()
        if (h.isEmpty()) return
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_PREFIX + h, System.currentTimeMillis())
            .apply()
    }

    fun wasSolvedRecently(context: Context, host: String, maxAgeMs: Long = 12L * 60L * 60L * 1000L): Boolean {
        val h = host.trim().lowercase()
        if (h.isEmpty()) return false
        val at = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(KEY_PREFIX + h, 0L)
        if (at <= 0L) return false
        return System.currentTimeMillis() - at <= maxAgeMs
    }
}
