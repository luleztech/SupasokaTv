import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supasoka/config/api_config.dart';

/// Lightweight HTTP probes — no platform connectivity plugin required.
/// Distinguishes "no internet" from "our backend is slow/down".
class NetworkReachability {
  NetworkReachability._();

  static const _generalProbes = [
    'https://connectivitycheck.gstatic.com/generate_204',
    'https://www.cloudflare.com/cdn-cgi/trace',
    'https://www.example.com',
  ];

  /// True when the device can reach the public internet (Wi‑Fi or mobile data).
  static Future<bool> hasGeneralInternet({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (kIsWeb) return true;

    for (final raw in _generalProbes) {
      try {
        final uri = Uri.parse(raw);
        final res = await http.head(uri).timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 400) return true;
      } catch (_) {}

      try {
        final uri = Uri.parse(raw);
        final res = await http.get(uri).timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 400) return true;
      } catch (_) {}
    }
    return false;
  }

  /// True when our API origin responds (may fail on slow Wi‑Fi even with internet).
  static Future<bool> canReachBackend({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final origin = apiConfigUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (origin.isEmpty) return false;

    try {
      final uri = Uri.parse('$origin/api/v1/public/config-meta').replace(
        queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
      );
      final res = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        },
      ).timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// App may proceed when either general internet or our backend is reachable.
  static Future<bool> canProceedOnline({
    Duration generalTimeout = const Duration(seconds: 5),
    Duration backendTimeout = const Duration(seconds: 10),
  }) async {
    if (await hasGeneralInternet(timeout: generalTimeout)) return true;
    return canReachBackend(timeout: backendTimeout);
  }
}
