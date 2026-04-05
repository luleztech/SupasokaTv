/// Default API origin (same as viewer app production). Override in Settings or
/// `--dart-define=API_BASE_URL=https://…`.
const String kDefaultAdminApiBaseUrl = 'https://supasokatv-production.up.railway.app';

const String _kApiBaseUrlEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');

/// Compile-time API URL override (optional).
String get adminApiBaseUrlFromEnvironment => _kApiBaseUrlEnv.trim();
