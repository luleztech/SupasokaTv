import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/services/premium_recovery.dart';
import 'package:supasoka/services/playback_service.dart';
import 'package:supasoka/services/user_identity.dart';

/// Local premium expiry (mirrors server — server is authoritative).
class SubscriptionStore {
  SubscriptionStore._();

  static const _kUntilMs = 'supasoka_premium_until_ms';
  static const _kPlanId = 'supasoka_premium_plan_id';

  /// Keeps Akaunti / Malipo in sync without prop drilling.
  static final ValueNotifier<DateTime?> premiumUntilNotifier = ValueNotifier<DateTime?>(null);

  static Timer? _localExpiryTimer;

  static void _cancelLocalExpiryTimer() {
    _localExpiryTimer?.cancel();
    _localExpiryTimer = null;
  }

  /// Locks channels locally at the exact server expiry time (no wait for poll/sync).
  static void _scheduleLocalExpiry(int untilMs) {
    _cancelLocalExpiryTimer();
    final delayMs = untilMs - DateTime.now().millisecondsSinceEpoch;
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
    return DateTime.fromMillisecondsSinceEpoch(ms).isAfter(DateTime.now());
  }

  static Future<void> clearLocalPremium() async {
    _cancelLocalExpiryTimer();
    invalidatePlaybackCache();
    final p = await SharedPreferences.getInstance();
    await p.remove(_kUntilMs);
    await p.remove(_kPlanId);
    premiumUntilNotifier.value = null;
  }

  static Future<void> purgeExpiredLocalPremium() async {
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
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_kUntilMs);
    if (ms == null || !_isActiveMs(ms)) {
      if (ms != null) await clearLocalPremium();
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<String?> premiumPlanId() async {
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
    if (!end.isAfter(DateTime.now())) {
      await clearLocalPremium();
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kUntilMs, premiumUntilMs);
    premiumUntilNotifier.value = end;
    _scheduleLocalExpiry(premiumUntilMs);
  }

  static bool isPremiumActiveLocal() {
    return premiumUntilNotifier.value?.isAfter(DateTime.now()) ?? false;
  }

  /// Server is authoritative — use before opening paid channels.
  static Future<bool> syncAndCheckPremiumActive() async {
    await syncPremiumFromBackend();
    return isPremiumActiveLocal();
  }

  /// Sync premium status from backend (authoritative for all users).
  static Future<void> syncPremiumFromBackend() async {
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
      }).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['ok'] != true) return;

      final rawUntil = j['premiumUntilMs'];
      final premiumUntilMs = rawUntil is int
          ? rawUntil
          : rawUntil is num
              ? rawUntil.toInt()
              : null;

      if (premiumUntilMs != null && _isActiveMs(premiumUntilMs)) {
        final p = await SharedPreferences.getInstance();
        await p.setInt(_kUntilMs, premiumUntilMs);
        premiumUntilNotifier.value = DateTime.fromMillisecondsSinceEpoch(premiumUntilMs);
        _scheduleLocalExpiry(premiumUntilMs);
        return;
      }

      final hasPending = await PremiumRecovery.hasRecentPendingPayment();
      if (hasPending) {
        return;
      }

      invalidatePlaybackCache();
      await clearLocalPremium();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SubscriptionStore.syncPremiumFromBackend failed (${e.runtimeType})');
      }
      await purgeExpiredLocalPremium();
    }
  }
}
