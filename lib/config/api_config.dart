import 'package:flutter/foundation.dart';
import 'package:supasoka/config/api_host.dart';
import 'package:supasoka/config/deployment.dart';

/// Set at build time to force a base URL (wins over defaults below).
const String _kApiBaseUrlEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');

/// Matches backend default `PORT` in `backend/src/config/env.ts` for local `npm run dev`.
const String kLocalApiBaseUrl = 'http://localhost:8080';

/// Set `true` to point **web debug** at [kLocalApiBaseUrl] (local Node). Default is `false` so
/// `flutter run -d chrome` uses the same host as [kRailwayApiBaseUrl] and config loads without a local API.
const bool kUseLocalApiOnWeb = bool.fromEnvironment('USE_LOCAL_API', defaultValue: false);

/// Effective backend base URL (no trailing slash).
///
/// - If `API_BASE_URL` is passed to the compiler, that value is used.
/// - **Web + debug** only uses `localhost:8080` when `USE_LOCAL_API=true` is passed; otherwise
///   it uses [kRailwayApiBaseUrl] (same as release) so Chrome is not stuck on a dead local host.
/// - **Android emulator**: `localhost` / `127.0.0.1` are rewritten to `10.0.2.2` so the device reaches your PC.
///
/// Override: `--dart-define=API_BASE_URL=…` or `flutter build apk --dart-define-from-file=dart_defines.json`
String get apiConfigUrl {
  final fromEnv = _kApiBaseUrlEnv.trim();
  if (fromEnv.isNotEmpty) {
    final resolved = rewriteLocalApiHost(fromEnv);
    // Web: a leftover `API_BASE_URL=http://localhost:8080` in launch / defines hits a dead host in the
    // browser. Use the deployed API unless the dev explicitly passed `USE_LOCAL_API=true`.
    if (kIsWeb &&
        !kUseLocalApiOnWeb &&
        (resolved.contains('127.0.0.1') || resolved.toLowerCase().contains('localhost'))) {
      return rewriteLocalApiHost(kRailwayApiBaseUrl);
    }
    return resolved;
  }
  if (kIsWeb && kDebugMode && kUseLocalApiOnWeb) return kLocalApiBaseUrl;
  return rewriteLocalApiHost(kRailwayApiBaseUrl);
}
