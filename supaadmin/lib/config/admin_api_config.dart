/// Production API origin (same host as viewer `deployment.dart`). Override with
/// `--dart-define=API_BASE_URL=https://…` or optional URL override in Settings.
const String kDefaultAdminApiBaseUrl = 'https://supasokatv-production.up.railway.app';

const String _kApiBaseUrlEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');

/// Compile-time API URL override (optional).
String get adminApiBaseUrlFromEnvironment => _kApiBaseUrlEnv.trim();

/// Railway header `X-Admin-Key` — must match env `ADMIN_API_KEY` on the API (EaAdmin-style).
///
/// **Release builds:** pass `--dart-define=ADMIN_API_KEY=your_secret`
///
/// **Private / internal APKs:** you may paste the same key here instead of leaving empty
/// (do not commit real secrets to a public repo).
const String _kAdminApiKeyFromEnv = String.fromEnvironment('ADMIN_API_KEY', defaultValue: '');
const String kOptionalInSourceAdminApiKey = '';

String get resolvedBundledAdminApiKey {
  final e = _kAdminApiKeyFromEnv.trim();
  if (e.isNotEmpty) return e;
  return kOptionalInSourceAdminApiKey.trim();
}
