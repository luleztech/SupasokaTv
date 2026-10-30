import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/services/link_probe.dart';

/// Lightweight probes. A Wi‑Fi link is online when any of these succeed:
/// our API, a public HTTPS check, or a direct route to a public address.
/// One blocked host (often Google on café Wi‑Fi) must not look like "no internet".
class NetworkReachability {
  NetworkReachability._();

  static const _headers = {
    'Accept': '*/*',
    'Cache-Control': 'no-cache',
    'User-Agent': 'Supasoka/1.1',
  };

  /// True when the device can reach the public internet (Wi‑Fi or mobile data).
  static Future<bool> hasGeneralInternet({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (kIsWeb) return true;
    return _anySuccess([
      _httpResponds('https://connectivitycheck.gstatic.com/generate_204', timeout),
      _httpResponds('https://www.cloudflare.com/cdn-cgi/trace', timeout),
      probePublicRoute(timeout),
    ], timeout + const Duration(seconds: 1));
  }

  /// True when our API origin responds.
  static Future<bool> canReachBackend({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final origin = apiConfigUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (origin.isEmpty) return false;
    final uri = Uri.parse('$origin/api/v1/public/config-meta').replace(
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
    );
    try {
      final res = await http
          .get(uri, headers: _headers)
          .timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// App may proceed when either general internet or our backend is reachable.
  static Future<bool> canProceedOnline({
    Duration generalTimeout = const Duration(seconds: 4),
    Duration backendTimeout = const Duration(seconds: 8),
  }) {
    if (kIsWeb) return Future.value(true);
    return _anySuccess([
      canReachBackend(timeout: backendTimeout),
      hasGeneralInternet(timeout: generalTimeout),
    ], backendTimeout + const Duration(seconds: 1));
  }

  static Future<bool> _httpResponds(String raw, Duration timeout) async {
    try {
      final res = await http.get(Uri.parse(raw), headers: _headers).timeout(timeout);
      return res.statusCode > 0;
    } catch (_) {
      return false;
    }
  }

  /// Completes as soon as one check is true. Does not wait out the failures.
  static Future<bool> _anySuccess(List<Future<bool>> checks, Duration cap) {
    if (checks.isEmpty) return Future.value(false);
    final done = Completer<bool>();
    var left = checks.length;
    for (final check in checks) {
      check.then((ok) {
        if (ok && !done.isCompleted) done.complete(true);
      }, onError: (_) {}).whenComplete(() {
        left -= 1;
        if (left == 0 && !done.isCompleted) done.complete(false);
      });
    }
    return done.future.timeout(cap, onTimeout: () => false);
  }
}
