import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/services/playback_service.dart';
import 'package:supasoka/services/user_identity.dart';

/// Local premium expiry (mirrors server — server is authoritative).
class SubscriptionStore {
  SubscriptionStore._();

  static const _kUntilMs = 'supasoka_premium_until_ms';
  static const _kPlanId = 'supasoka_premium_plan_id';
  static const _kServerOffsetMs = 'supasoka_server_clock_offset_ms';

  /// Keeps Akaunti / Malipo in sync without prop drilling.
  static final ValueNotifier<DateTime?> premiumUntilNotifier = ValueNotifier<DateTime?>(null);

  static Timer? _localExpiryTimer;
  static Future<void>? _inflightSync;
  static DateTime? _lastSyncAttemptAt;
  /// Keeps a just-confirmed unlock if the premium read is a moment behind the payment.
  static DateTime? _trustedGrantAt;
  static const _minSyncInterval = Duration(seconds: 45);
  static const _syncTimeout = Duration(seconds: 20);

  /// Server clock minus handset clock. A handset with a wrong date used to lock a
  /// paying customer out early (or keep an expired one in); expiry is now judged
  /// on the server's clock.
  static int _serverOffsetMs = 0;
  static bool _offsetLoaded = false;

  static Future<void> _ensureOffsetLoaded() async {
    if (_offsetLoaded) return;
    final p = await SharedPreferences.getInstance();
    _serverOffsetMs = p.getInt(_kServerOffsetMs) ?? 0;
    _offsetLoaded = true;
  }

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch + _serverOffsetMs;

  static Future<void> _learnServerTime(Object? serverNowMs) async {
    final raw = serverNowMs is num ? serverNowMs.toInt() : null;
    if (raw == null || raw <= 0) return;
    final offset = raw - DateTime.now().millisecondsSinceEpoch;
    // Ignore absurd values (> 400 days) rather than trusting a broken response.
    if (offset.abs() > 400 * 24 * 60 * 60 * 1000) return;
    _serverOffsetMs = offset;
    _offsetLoaded = true;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kServerOffsetMs, offset);
  }

  static void _cancelLocalExpiryTimer() {
    _localExpiryTimer?.cancel();
    _localExpiryTimer = null;
  }

  /// Locks channels locally at the exact server expiry time (no wait for poll/sync).
  static void _scheduleLocalExpiry(int untilMs) {
    _cancelLocalExpiryTimer();
    final delayMs = untilMs - _nowMs();
    if (delayMs <= 0) {
      unawaited(clearLocalPremium());
      return;
    }
    _localExpiryTimer = Timer(Duration(milliseconds: delayMs + 250), () {
      unawaited(purgeExpiredLocalPremium());
    });
  }

  static bool _isActiveMs(int? ms) {
    if (ms == null) return false;
    return ms > _nowMs();
  }

  static Future<void> clearLocalPremium() async {
    _cancelLocalExpiryTimer();
    _trustedGrantAt = null;
    invalidatePlaybackCache();
    final p = await SharedPreferences.getInstance();
    await p.remove(_kUntilMs);
    await p.remove(_kPlanId);
    premiumUntilNotifier.value = null;
  }

  static Future<void> purgeExpiredLocalPremium() async {
    await _ensureOffsetLoaded();
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_kUntilMs);
    if (ms == null) {
      premiumUntilNotifier.value = null;
      _cancelLocalExpiryTimer();
      return;
    }
    if (!_isActiveMs(ms)) {
      await clearLocalPremium();
      return;
    }
    premiumUntilNotifier.value = DateTime.fromMillisecondsSinceEpoch(ms);
    _scheduleLocalExpiry(ms);
  }

  static Future<DateTime?> premiumUntil() async {
    await _ensureOffsetLoaded();
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_kUntilMs);
    if (ms == null || !_isActiveMs(ms)) {
      if (ms != null) await clearLocalPremium();
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<String?> premiumPlanId() async {
    await _ensureOffsetLoaded();
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_kUntilMs);
    if (ms == null || !_isActiveMs(ms)) return null;
    return p.getString(_kPlanId);
  }

  static Future<void> refreshNotifierFromPrefs() async {
    await purgeExpiredLocalPremium();
  }

  /// Sets expiry from server confirmation (authoritative).
  static Future<void> setPremiumUntilMs(int premiumUntilMs) async {
    final end = DateTime.fromMillisecondsSinceEpoch(premiumUntilMs);
    // Allow small handset clock skew vs server-authoritative expiry.
    await _ensureOffsetLoaded();
    if (premiumUntilMs <= _nowMs() - const Duration(minutes: 5).inMilliseconds) {
      await clearLocalPremium();
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kUntilMs, premiumUntilMs);
    premiumUntilNotifier.value = end;
    _trustedGrantAt = DateTime.now();
    _scheduleLocalExpiry(premiumUntilMs);
    // Drop every cached "lipia kwanza" result so all paid channels open.
    invalidatePlaybackCache();
  }

  static bool isPremiumActiveLocal() {
    final until = premiumUntilNotifier.value;
    return until != null && until.millisecondsSinceEpoch > _nowMs();
  }

  /// Server is authoritative — use before opening paid channels.
  static Future<bool> syncAndCheckPremiumActive() async {
    await syncPremiumFromBackend(force: true);
    return isPremiumActiveLocal();
  }

  /// Sync premium status from backend (authoritative for all users).
  ///
  /// Dedupes concurrent calls and rate-limits to avoid flooding the API
  /// (timeouts / socket errors under poor network).
  static Future<void> syncPremiumFromBackend({bool force = false}) async {
    if (_inflightSync != null) return _inflightSync!;

    final now = DateTime.now();
    if (!force &&
        _lastSyncAttemptAt != null &&
        now.difference(_lastSyncAttemptAt!) < _minSyncInterval) {
      return;
    }
    _lastSyncAttemptAt = now;

    _inflightSync = _syncPremiumFromBackendImpl();
    try {
      await _inflightSync;
    } finally {
      _inflightSync = null;
    }
  }

  static Future<void> _syncPremiumFromBackendImpl() async {
    await purgeExpiredLocalPremium();

    final base = apiConfigUrl.trim();
    if (base.isEmpty) return;

    final userId = await UserIdentity.getOrCreatePublicId();
    final origin = base.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/user-premium/$userId');

    try {
      final res = await http.get(uri, headers: const {
        'Cache-Control': 'no-cache',
        'Accept': 'application/json',
      }).timeout(_syncTimeout);

      if (res.statusCode != 200) return;

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['ok'] != true) return;
      await _learnServerTime(j['serverNowMs']);

      final rawUntil = j['premiumUntilMs'];
      final premiumUntilMs = rawUntil is int
          ? rawUntil
          : rawUntil is num
              ? rawUntil.toInt()
              : null;

      if (premiumUntilMs != null && _isActiveMs(premiumUntilMs)) {
        final previousMs = premiumUntilNotifier.value?.millisecondsSinceEpoch;
        final justUnlocked = !isPremiumActiveLocal();
        final p = await SharedPreferences.getInstance();
        await p.setInt(_kUntilMs, premiumUntilMs);
        premiumUntilNotifier.value = DateTime.fromMillisecondsSinceEpoch(premiumUntilMs);
        _scheduleLocalExpiry(premiumUntilMs);
        _trustedGrantAt = null;
        if (justUnlocked || previousMs != premiumUntilMs) invalidatePlaybackCache();
        return;
      }

      final grantAt = _trustedGrantAt;
      if (grantAt != null &&
          DateTime.now().difference(grantAt) < const Duration(minutes: 3) &&
          isPremiumActiveLocal()) {
        return;
      }

      // The server has never heard of this id (reinstall, wiped data, id re-created):
      // re-attach through the saved phone number before concluding "no package".
      if (j['userExists'] == false) {
        final phone = await UserIdentity.getSavedPhoneNumber();
        final reg = await UserIdentity.registerWithBackend(phone: phone);
        final recoveredMs = reg.premiumUntilMs;
        if (recoveredMs != null && _isActiveMs(recoveredMs)) {
          final p = await SharedPreferences.getInstance();
          await p.setInt(_kUntilMs, recoveredMs);
          premiumUntilNotifier.value = DateTime.fromMillisecondsSinceEpoch(recoveredMs);
          _scheduleLocalExpiry(recoveredMs);
          _trustedGrantAt = null;
          invalidatePlaybackCache();
          return;
        }
      }

      // Server says expired / null — always clear local. Pending payment recovery
      // must confirm unlock explicitly; it must not keep a stale premium window.
      _trustedGrantAt = null;
      invalidatePlaybackCache();
      await clearLocalPremium();
    } catch (e) {
      // Transient network noise — keep local premium cache; avoid log spam.
      if (kDebugMode) {
        final name = e.runtimeType.toString();
        if (name != 'TimeoutException' && !name.contains('SocketException')) {
          debugPrint('SubscriptionStore.syncPremiumFromBackend failed ($name)');
        }
      }
      await purgeExpiredLocalPremium();
    }
  }
}
