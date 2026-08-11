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

/// Local premium mirror only — never wipe the stable public id / phone on update.
const _localPremiumCacheKeys = <String>[
  'supasoka_premium_until_ms',
  'supasoka_premium_plan_id',
];

/// Suffix charset aligned with backend `^User-[A-Za-z2-9]{5}$` (no 0/O/1/l ambiguity).
const _suffixChars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';

String _randomSuffix5() {
  final r = Random.secure();
  return List.generate(5, (_) => _suffixChars[r.nextInt(_suffixChars.length)]).join();
}

/// Stable viewer id: `User-xxxxx`. Persisted across app updates; recovered by phone
/// when the backend still has an active subscription for that number.
class UserIdentity {
  UserIdentity._();

  /// On a true reinstall marker change, clear stale *local premium cache* only.
  /// Never delete `User-xxxxx` or phone — that caused subscribed users to lose access
  /// after updates / OEM data quirks. Server sync remains authoritative for expiry.
  static Future<bool> resetIdentityIfFreshInstall() async {
    final p = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    final installMs = info.installTime?.millisecondsSinceEpoch;
    if (installMs == null) return false;

    final storedInstallMs = p.getInt(_prefsInstallMs);
    if (storedInstallMs != null && storedInstallMs != installMs) {
      for (final key in _localPremiumCacheKeys) {
        await p.remove(key);
      }
      await p.setInt(_prefsInstallMs, installMs);
      if (kDebugMode) {
        debugPrint(
          'UserIdentity: install marker changed — kept public id/phone; cleared local premium cache',
        );
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

  /// Persist a server-recovered id (active subscription found by phone).
  static Future<void> adoptPublicId(String publicId) async {
    final id = publicId.trim();
    if (!_isValidPublicId(id)) return;
    final p = await SharedPreferences.getInstance();
    final current = p.getString(_prefsPublicId)?.trim();
    if (current == id) return;
    await p.setString(_prefsPublicId, id);
    if (kDebugMode) {
      debugPrint('UserIdentity: adopted recovered public id $id (was $current)');
    }
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

  /// Upserts this device on the server. When [phone] matches an active subscriber,
  /// the server returns the old `publicId` and we adopt it locally.
  static Future<({String publicId, bool recovered, int? premiumUntilMs})> registerWithBackend({
    String? phone,
  }) async {
    final base = apiConfigUrl.trim();
    final localId = await getOrCreatePublicId();
    if (base.isEmpty) {
      return (publicId: localId, recovered: false, premiumUntilMs: null);
    }

    final origin = base.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/register-user').replace(
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
    );
    final body = <String, dynamic>{
      'publicId': localId,
      'profileUsername': localId,
    };
    final phoneTrim = phone?.trim();
    if (phoneTrim != null && phoneTrim.isNotEmpty) {
      body['phone'] = phoneTrim;
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
        if (phoneTrim != null && phoneTrim.isNotEmpty) {
          await savePhoneNumber(phoneTrim);
        }
        try {
          final j = jsonDecode(res.body);
          if (j is Map<String, dynamic>) {
            final serverId = '${j['publicId'] ?? ''}'.trim();
            final recovered = j['recovered'] == true;
            final rawUntil = j['premiumUntilMs'];
            final premiumUntilMs = rawUntil is int
                ? rawUntil
                : rawUntil is num
                    ? rawUntil.toInt()
                    : null;
            if (_isValidPublicId(serverId)) {
              await adoptPublicId(serverId);
              return (
                publicId: serverId,
                recovered: recovered || serverId != localId,
                premiumUntilMs: premiumUntilMs,
              );
            }
          }
        } catch (_) {
          /* older servers may still return `{ ok: true }` only */
        }
        return (publicId: localId, recovered: false, premiumUntilMs: null);
      }
      if (kDebugMode) {
        debugPrint('UserIdentity.registerWithBackend: HTTP ${res.statusCode}');
      }
    } catch (e, _) {
      if (kDebugMode) {
        debugPrint('UserIdentity.registerWithBackend failed (${e.runtimeType})');
      }
    }
    return (publicId: localId, recovered: false, premiumUntilMs: null);
  }
}
