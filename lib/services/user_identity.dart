import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supasoka/config/api_config.dart';

const _prefsPublicId = 'supasoka_public_user_id';
const _prefsPublicPhone = 'supasoka_public_user_phone';
const _prefsInstallMs = 'supasoka_install_time_ms';

/// Keys cleared on reinstall so identity and subscription never survive a fresh install.
const _identityResetKeys = <String>[
  _prefsPublicId,
  _prefsPublicPhone,
  'supasoka_premium_until_ms',
  'supasoka_premium_plan_id',
  'pendingPaymentOrderId',
  'pendingPaymentPlanId',
  'pendingPaymentPhone',
  'pendingPaymentProvider',
  'pendingPaymentCreatedAtMs',
];

/// Suffix charset aligned with backend `^User-[A-Za-z2-9]{5}$` (no 0/O/1/l ambiguity).
const _suffixChars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';

String _randomSuffix5() {
  final r = Random.secure();
  return List.generate(5, (_) => _suffixChars[r.nextInt(_suffixChars.length)]).join();
}

/// Stable viewer id: `User-xxxxx` (unique suffix). New id on every app reinstall.
class UserIdentity {
  UserIdentity._();

  /// Detect reinstall (or backup restore after reinstall) and wipe prior identity/subscription prefs.
  /// Call once at cold start before reading premium from local storage.
  static Future<bool> resetIdentityIfFreshInstall() async {
    final p = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    final installMs = info.installTime?.millisecondsSinceEpoch;
    if (installMs == null) return false;

    final storedInstallMs = p.getInt(_prefsInstallMs);
    if (storedInstallMs != null && storedInstallMs != installMs) {
      for (final key in _identityResetKeys) {
        await p.remove(key);
      }
      await p.setInt(_prefsInstallMs, installMs);
      if (kDebugMode) {
        debugPrint('UserIdentity: fresh install detected — new user id will be issued');
      }
      return true;
    }

    if (storedInstallMs == null) {
      await p.setInt(_prefsInstallMs, installMs);
    }
    return false;
  }

  /// Returns existing `User-xxxxx` or creates and persists a new one.
  static Future<String> getOrCreatePublicId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_prefsPublicId)?.trim();
    if (id != null && id.isNotEmpty && _isValidPublicId(id)) {
      return id;
    }
    id = 'User-${_randomSuffix5()}';
    await p.setString(_prefsPublicId, id);
    return id;
  }

  static bool _isValidPublicId(String id) {
    if (!id.startsWith('User-') || id.length != 10) return false;
    final suffix = id.substring(5);
    return RegExp(r'^[A-Za-z2-9]{5}$').hasMatch(suffix);
  }

  static Future<void> savePhoneNumber(String phone) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsPublicPhone, phone.trim());
  }

  static Future<String?> getSavedPhoneNumber() async {
    final p = await SharedPreferences.getInstance();
    final phone = p.getString(_prefsPublicPhone)?.trim();
    if (phone == null || phone.isEmpty) return null;
    return phone;
  }

  /// Upserts this device on the server so admins see new installs under Users.
  static Future<void> registerWithBackend({String? phone}) async {
    final base = apiConfigUrl.trim();
    if (base.isEmpty) return;

    final publicId = await getOrCreatePublicId();
    final origin = base.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/register-user').replace(
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
    );
    final body = <String, dynamic>{
      'publicId': publicId,
      'profileUsername': publicId,
    };
    if (phone != null && phone.trim().isNotEmpty) {
      body['phone'] = phone.trim();
    }

    try {
      final res = await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Cache-Control': 'no-cache',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (phone != null && phone.trim().isNotEmpty) {
          await savePhoneNumber(phone);
        }
        return;
      }
      if (kDebugMode) {
        debugPrint('UserIdentity.registerWithBackend: HTTP ${res.statusCode}');
      }
    } catch (e, _) {
      if (kDebugMode) {
        debugPrint('UserIdentity.registerWithBackend failed (${e.runtimeType})');
      }
    }
  }
}
