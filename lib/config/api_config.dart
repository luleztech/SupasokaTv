import 'package:flutter/foundation.dart';
import 'package:supasoka/config/deployment.dart';

/// Set at build time to force a base URL (wins over defaults below).
const String _kApiBaseUrlEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');

/// Matches backend default `PORT` in `backend/src/config/env.ts` for local `npm run dev`.
const String kLocalApiBaseUrl = 'http://localhost:8080';

/// Effective backend base URL (no trailing slash).
///
/// - If `API_BASE_URL` is passed to the compiler, that value is used.
/// - **Web + debug** (`flutter run -d chrome`): [kLocalApiBaseUrl] so the browser
///   talks to a local API (avoids calling a missing remote host).
/// - Otherwise: [kRailwayApiBaseUrl] (set in `deployment.dart`; may be empty until you configure it).
///
/// Override: `--dart-define=API_BASE_URL=…` or `flutter build apk --dart-define-from-file=dart_defines.json`
String get apiConfigUrl {
  final fromEnv = _kApiBaseUrlEnv.trim();
  if (fromEnv.isNotEmpty) return fromEnv;
  if (kIsWeb && kDebugMode) return kLocalApiBaseUrl;
  return kRailwayApiBaseUrl;
}
