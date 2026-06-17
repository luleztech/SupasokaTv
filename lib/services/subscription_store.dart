import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/services/premium_recovery.dart';
import 'package:supasoka/services/user_identity.dart';

/// Local premium expiry (mirrors server — server is authoritative).
class SubscriptionStore {
  SubscriptionStore._();

  static const _kUntilMs = 'supasoka_premium_until_ms';
  static const _kPlanId = 'supasoka_premium_plan_id';

  /// Keeps Akaunti / Malipo in sync without prop drilling.
  static final ValueNotifier<DateTime?> premiumUntilNotifier = ValueNotifier<DateTime?>(null);

  static bool _isActiveMs(int? ms) {
    if (ms == null) return false;
    return DateTime.fromMillisecondsSinceEpoch(ms).isAfter(DateTime.now());
  }

  static Future<void> clearLocalPremium() async {
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
      return;
    }
    if (!_isActiveMs(ms)) {
      await clearLocalPremium();
      return;
    }
    premiumUntilNotifier.value = DateTime.fromMillisecondsSinceEpoch(ms);
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
      final userExists = j['userExists'] == true;

      if (premiumUntilMs != null && _isActiveMs(premiumUntilMs)) {
        final p = await SharedPreferences.getInstance();
        await p.setInt(_kUntilMs, premiumUntilMs);
        premiumUntilNotifier.value = DateTime.fromMillisecondsSinceEpoch(premiumUntilMs);
        return;
      }

      if (userExists) {
        await PremiumRecovery.clearPendingPaymentState();
      }
      await clearLocalPremium();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SubscriptionStore.syncPremiumFromBackend failed (${e.runtimeType})');
      }
      await purgeExpiredLocalPremium();
    }
  }
}
