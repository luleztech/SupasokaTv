import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/services/premium_recovery.dart';
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

  /// Stacks on top of an active subscription if still valid. Prefer server [confirm-zeno-premium] for exact duration from admin malipo row.
  static Future<void> activatePlan(String planId) async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final id = planId.trim().toLowerCase();
    final dur = switch (id) {
      'weekly' => const Duration(days: 7),
      'monthly' => const Duration(days: 30),
      'yearly' => const Duration(days: 365),
      'annual' => const Duration(days: 365),
      'quarterly' ||
      'quarter' ||
      'three_month' ||
      'trimestrial' ||
      'miezi_3' ||
      'miezi3' =>
        const Duration(days: 90),
      'daily' => const Duration(days: 1),
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
  /// Never removes a still-valid local subscription when the server row is missing or lagging.
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

      final p = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final localMs = p.getInt(_kUntilMs);
      final localEnd = localMs != null ? DateTime.fromMillisecondsSinceEpoch(localMs) : null;
      final localActive = localEnd != null && localEnd.isAfter(now);

      if (premiumUntilMs != null) {
        final serverEnd = DateTime.fromMillisecondsSinceEpoch(premiumUntilMs);
        var mergedMs = premiumUntilMs;
        // Keep the longer active window (do not shorten on sync).
        if (localActive && localEnd.isAfter(serverEnd)) {
          mergedMs = localEnd.millisecondsSinceEpoch;
        }
        await p.setInt(_kUntilMs, mergedMs);
        premiumUntilNotifier.value = DateTime.fromMillisecondsSinceEpoch(mergedMs);
        return;
      }

      // Server has no premium:
      // - keep local premium only while a recent payment is still pending;
      // - otherwise trust backend (important for admin "remove premium").
      if (localActive) {
        final hasPending = await PremiumRecovery.hasRecentPendingPayment();
        if (!userExists || hasPending) {
          premiumUntilNotifier.value = localEnd;
          return;
        }
      }

      await p.remove(_kUntilMs);
      await p.remove(_kPlanId);
      premiumUntilNotifier.value = null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SubscriptionStore.syncPremiumFromBackend failed (${e.runtimeType})');
      }
    }
  }
}
