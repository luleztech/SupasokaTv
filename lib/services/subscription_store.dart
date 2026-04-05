import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
