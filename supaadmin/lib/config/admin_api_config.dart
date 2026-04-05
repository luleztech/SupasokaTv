/// Default API origin (same as viewer app production). Override in Settings or
/// `--dart-define=API_BASE_URL=https://…`.
const String kDefaultAdminApiBaseUrl = 'https://supasokatv-production.up.railway.app';

const String _kApiBaseUrlEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');
const String _kAdminApiKeyEnv = String.fromEnvironment('ADMIN_API_KEY', defaultValue: '');

/// Compile-time overrides (optional).
String get adminApiBaseUrlFromEnvironment => _kApiBaseUrlEnv.trim();
String get adminApiKeyFromEnvironment => _kAdminApiKeyEnv.trim();
