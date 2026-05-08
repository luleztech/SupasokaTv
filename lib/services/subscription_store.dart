import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/services/user_identity.dart';

/// Local premium expiry (set after successful Malipo flow).
class SubscriptionStore {
  SubscriptionStore._();

  static const _kUntilMs = 'supasoka_premium_until_ms';
  static const _kPlanId = 'supasoka_premium_plan_id';

  /// Keeps Akaunti / Malipo in sync without prop drilling.
  static final ValueNotifier<DateTime?> premiumUntilNotifier = ValueNotifier<DateTime?>(null);

  static Future<DateTime?> premiumUntil() async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_kUntilMs);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<String?> premiumPlanId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPlanId);
  }

  static Future<void> refreshNotifierFromPrefs() async {
    premiumUntilNotifier.value = await premiumUntil();
  }

  /// Sets expiry from server confirmation (same source as admin / other devices).
  static Future<void> setPremiumUntilMs(int premiumUntilMs) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kUntilMs, premiumUntilMs);
    premiumUntilNotifier.value = DateTime.fromMillisecondsSinceEpoch(premiumUntilMs);
  }

  /// Stacks on top of an active subscription if still valid.
  static Future<void> activatePlan(String planId) async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final dur = switch (planId) {
      'weekly' => const Duration(days: 7),
      'monthly' => const Duration(days: 30),
      'yearly' => const Duration(days: 365),
      _ => const Duration(days: 30),
    };
    final existingMs = p.getInt(_kUntilMs);
    var start = now;
    if (existingMs != null) {
      final ex = DateTime.fromMillisecondsSinceEpoch(existingMs);
      if (ex.isAfter(now)) start = ex;
    }
    final end = start.add(dur);
    await p.setInt(_kUntilMs, end.millisecondsSinceEpoch);
    await p.setString(_kPlanId, planId);
    premiumUntilNotifier.value = end;
  }

  /// Sync premium status from backend (for admin-granted subscriptions).
  static Future<void> syncPremiumFromBackend() async {
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

      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        if (j['ok'] == true) {
          final rawUntil = j['premiumUntilMs'];
          final premiumUntilMs = rawUntil is int
              ? rawUntil
              : rawUntil is num
                  ? rawUntil.toInt()
                  : null;
          if (premiumUntilMs != null) {
            final end = DateTime.fromMillisecondsSinceEpoch(premiumUntilMs);
            final p = await SharedPreferences.getInstance();
            await p.setInt(_kUntilMs, premiumUntilMs);
            premiumUntilNotifier.value = end;
          } else {
            // No premium
            final p = await SharedPreferences.getInstance();
            await p.remove(_kUntilMs);
            await p.remove(_kPlanId);
            premiumUntilNotifier.value = null;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SubscriptionStore.syncPremiumFromBackend failed (${e.runtimeType})');
      }
    }
  }
}
