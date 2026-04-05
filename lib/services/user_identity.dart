import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supasoka/config/api_config.dart';

const _prefsPublicId = 'supasoka_public_user_id';

/// Suffix charset aligned with backend `^User-[A-Za-z2-9]{5}$` (no 0/O/1/l ambiguity).
const _suffixChars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';

String _randomSuffix5() {
  final r = Random.secure();
  return List.generate(5, (_) => _suffixChars[r.nextInt(_suffixChars.length)]).join();
}

/// Stable viewer id: `User-xxxxx` (unique suffix). Persisted locally; registered on the API when online.
class UserIdentity {
  UserIdentity._();

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

  /// Upserts this device on the server so admins see new installs under Users.
  static Future<void> registerWithBackend() async {
    final base = apiConfigUrl.trim();
    if (base.isEmpty) return;

    final publicId = await getOrCreatePublicId();
    final origin = base.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/register-user').replace(
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
    );
    try {
      await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Cache-Control': 'no-cache',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'publicId': publicId,
              'profileUsername': publicId,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      /* offline / wrong URL — id stays local; will retry on next launch or refresh */
    }
  }
}
