import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supasoka/config/api.dart';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/config/payment_helpers.dart'
    show isPaymentCompleted, isPaymentTerminalFailure, paymentStatusFromCheckResponse;
import 'package:supasoka/services/app_update_service.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/services/user_identity.dart';

/// Background recovery when the user paid but closed the app before premium was saved.
class PremiumRecovery {
  PremiumRecovery._();

  static const _pendingOrderKey = 'pendingPaymentOrderId';
  static const _pendingPlanKey = 'pendingPaymentPlanId';
  static const _pendingPhoneKey = 'pendingPaymentPhone';
  static const _pendingCreatedAtKey = 'pendingPaymentCreatedAtMs';

  /// Returns server [premiumUntilMs] when confirm succeeds.
  static Future<int?> confirmPremiumOnBackend({
    required String orderId,
    required String publicId,
    required String planId,
    required String phone,
  }) async {
    final base = apiConfigUrl.trim();
    if (base.isEmpty) return null;
    final origin = base.replaceAll(RegExp(r'/$'), '');
    final versionHeaders = await appVersionHeaders();
    final uris = [
      Uri.parse('$origin/api/v1/public/confirm-premium'),
    ];
    for (var attempt = 0; attempt < 5; attempt++) {
      final uri = uris[0];
      try {
        final res = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'Cache-Control': 'no-cache',
                ...versionHeaders,
              },
              body: jsonEncode({
                'orderId': orderId,
                'publicId': publicId,
                'planId': planId,
                'phone': phone,
              }),
            )
            .timeout(const Duration(seconds: 25));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            final j = jsonDecode(res.body) as Map<String, dynamic>;
            if (j['ok'] == true) {
              final raw = j['premiumUntilMs'];
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              if (raw is int && raw > nowMs) return raw;
              if (raw is num && raw.toInt() > nowMs) return raw.toInt();
            }
          } catch (_) {}
        } else if ((res.statusCode == 402 || res.statusCode == 409 || res.statusCode == 500) && attempt < 4) {
          await Future<void>.delayed(Duration(milliseconds: 1200 + (attempt * 900)));
          continue;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('PremiumRecovery.confirm failed: $e');
        }
        if (attempt < 4) {
          await Future<void>.delayed(Duration(milliseconds: 1000 + (attempt * 700)));
          continue;
        }
      }
    }
    return null;
  }

  /// After payment or when playback says premium required — sync server + local state.
  static Future<bool> ensurePremiumUnlocked() async {
    final reg = await UserIdentity.registerWithBackend(
      phone: (await UserIdentity.getSavedPhoneNumber()) ?? '',
    );
    if (reg.premiumUntilMs != null &&
        reg.premiumUntilMs! > DateTime.now().millisecondsSinceEpoch) {
      await SubscriptionStore.setPremiumUntilMs(reg.premiumUntilMs!);
      await SubscriptionStore.refreshNotifierFromPrefs();
      return true;
    }
    final recovered = await recoverPendingPaymentIfAny();
    await SubscriptionStore.syncPremiumFromBackend(force: true);
    final active =
        SubscriptionStore.premiumUntilNotifier.value?.isAfter(DateTime.now()) ?? false;
    if (active) return true;
    if (recovered) return true;

    final prefs = await SharedPreferences.getInstance();
    final orderId = prefs.getString(_pendingOrderKey)?.trim() ?? '';
    var planId = prefs.getString(_pendingPlanKey)?.trim() ?? '';
    final phone = prefs.getString(_pendingPhoneKey)?.trim() ?? '';
    final publicId = await UserIdentity.getOrCreatePublicId();

    // Prefer server reconcile via user-premium (heals missed webhooks).
    final rec = await fetchUserPremiumRecord(publicId);
    if (rec.premiumUntilMs != null) {
      final end = DateTime.fromMillisecondsSinceEpoch(rec.premiumUntilMs!);
      if (end.isAfter(DateTime.now())) {
        await SubscriptionStore.setPremiumUntilMs(rec.premiumUntilMs!);
        await _clearPendingOrderPrefs();
        await SubscriptionStore.refreshNotifierFromPrefs();
        return true;
      }
    }

    if (orderId.isEmpty) return false;

    if (planId.isEmpty) {
      try {
        final status = await paymentsApi.checkPaymentStatus(orderId);
        final fromStatus = status['intentPlanId'] ?? status['planId'];
        if (fromStatus is String && fromStatus.trim().isNotEmpty) {
          planId = fromStatus.trim();
          await prefs.setString(_pendingPlanKey, planId);
        }
        final premiumMs = status['premiumUntilMs'];
        if (status['activated'] == true && premiumMs is num) {
          final ms = premiumMs.toInt();
          if (ms > DateTime.now().millisecondsSinceEpoch) {
            await SubscriptionStore.setPremiumUntilMs(ms);
            await _clearPendingOrderPrefs();
            await SubscriptionStore.refreshNotifierFromPrefs();
            return true;
          }
        }
      } catch (_) {}
    }
    if (planId.isEmpty) return false;

    final serverUntil = await confirmPremiumOnBackend(
      orderId: orderId,
      publicId: publicId,
      planId: planId,
      phone: phone,
    );
    if (serverUntil != null) {
      await SubscriptionStore.setPremiumUntilMs(serverUntil);
      await _clearPendingOrderPrefs();
      await SubscriptionStore.refreshNotifierFromPrefs();
      return true;
    }
    return false;
  }

  static Future<void> _clearPendingOrderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingOrderKey);
    await prefs.remove(_pendingPlanKey);
    await prefs.remove(_pendingPhoneKey);
    await prefs.remove('pendingPaymentProvider');
    await prefs.remove(_pendingCreatedAtKey);
  }

  static Future<void> clearPendingPaymentState() async {
    await _clearPendingOrderPrefs();
  }

  static Future<void> markPendingPaymentCreatedNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pendingCreatedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<({bool userExists, int? premiumUntilMs})> fetchUserPremiumRecord(String publicId) async {
    final base = apiConfigUrl.trim();
    if (base.isEmpty) return (userExists: false, premiumUntilMs: null);
    final origin = base.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/user-premium/$publicId');
    try {
      final res = await http.get(uri, headers: const {
        'Cache-Control': 'no-cache',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return (userExists: false, premiumUntilMs: null);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['ok'] != true) return (userExists: false, premiumUntilMs: null);
      final raw = j['premiumUntilMs'];
      final premiumUntilMs = raw is int ? raw : raw is num ? raw.toInt() : null;
      return (userExists: j['userExists'] == true, premiumUntilMs: premiumUntilMs);
    } catch (_) {
      return (userExists: false, premiumUntilMs: null);
    }
  }

  /// Returns true while a pending payment is still fresh enough to trust local fallback premium.
  static Future<bool> hasRecentPendingPayment({
    Duration maxAge = const Duration(hours: 72),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final orderId = prefs.getString(_pendingOrderKey)?.trim();
    if (orderId == null || orderId.isEmpty) return false;

    final createdAtMs = prefs.getInt(_pendingCreatedAtKey);
    if (createdAtMs == null || createdAtMs <= 0) {
      await _clearPendingOrderPrefs();
      return false;
    }
    final ageMs = DateTime.now().millisecondsSinceEpoch - createdAtMs;
    if (ageMs <= maxAge.inMilliseconds) return true;

    // Stale pending marker should not block admin premium removal.
    await _clearPendingOrderPrefs();
    return false;
  }

  /// Completes premium for a paid order left in prefs (app closed mid-poll / timeout).
  static Future<bool> recoverPendingPaymentIfAny() async {
    final prefs = await SharedPreferences.getInstance();
    final orderId = prefs.getString(_pendingOrderKey)?.trim();
    if (orderId == null || orderId.isEmpty) return false;

    var planId = prefs.getString(_pendingPlanKey)?.trim() ?? '';
    final phone = prefs.getString(_pendingPhoneKey)?.trim() ?? '';

    try {
      final response = await paymentsApi.checkPaymentStatus(orderId);
      final paymentStatus = paymentStatusFromCheckResponse(response);
      if (isPaymentTerminalFailure(paymentStatus)) {
        await _clearPendingOrderPrefs();
        return false;
      }

      if (!isPaymentCompleted(paymentStatus)) return false;

      if (planId.isEmpty) {
        final fromStatus = response['intentPlanId'] ?? response['planId'];
        if (fromStatus is String && fromStatus.trim().isNotEmpty) {
          planId = fromStatus.trim();
          await prefs.setString(_pendingPlanKey, planId);
        }
      }
      if (planId.isEmpty) return false;

      final publicId = await UserIdentity.getOrCreatePublicId();
      var serverUntil = response['premiumUntilMs'];
      int? serverUntilMs;
      if (serverUntil is int) {
        serverUntilMs = serverUntil;
      } else if (serverUntil is num) {
        serverUntilMs = serverUntil.toInt();
      }

      if (serverUntilMs == null || serverUntilMs <= DateTime.now().millisecondsSinceEpoch) {
        final confirmed = await confirmPremiumOnBackend(
          orderId: orderId,
          publicId: publicId,
          planId: planId,
          phone: phone,
        );
        if (confirmed != null) serverUntilMs = confirmed;
      }

      if (serverUntilMs == null) {
        final rec = await fetchUserPremiumRecord(publicId);
        final raw = rec.premiumUntilMs;
        if (raw != null && raw > DateTime.now().millisecondsSinceEpoch) {
          serverUntilMs = raw;
        }
      }

      if (serverUntilMs != null && serverUntilMs > DateTime.now().millisecondsSinceEpoch) {
        await SubscriptionStore.setPremiumUntilMs(serverUntilMs);
        if (phone.isNotEmpty) {
          await UserIdentity.savePhoneNumber(phone);
          await UserIdentity.registerWithBackend(phone: phone);
        }
        await _clearPendingOrderPrefs();
        await SubscriptionStore.refreshNotifierFromPrefs();
        return true;
      }

      if (phone.isNotEmpty) {
        await UserIdentity.savePhoneNumber(phone);
        await UserIdentity.registerWithBackend(phone: phone);
      }

      await SubscriptionStore.syncPremiumFromBackend(force: true);
      await SubscriptionStore.refreshNotifierFromPrefs();
      return SubscriptionStore.premiumUntilNotifier.value?.isAfter(DateTime.now()) ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PremiumRecovery.recoverPendingPaymentIfAny failed: $e');
      }
      return false;
    }
  }
}
