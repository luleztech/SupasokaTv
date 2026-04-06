/// Single place the SupaAdmin app reads API settings (no Settings UI, no passwords).
/// Backend validates `X-Admin-Key` against Railway `ADMIN_API_KEY`.

const String kDefaultAdminApiBaseUrl = 'https://supasokatv-production.up.railway.app';

const String _kApiBaseUrlEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');
const String _kAdminApiKeyEnv = String.fromEnvironment('ADMIN_API_KEY', defaultValue: '');

/// **Before shipping SupaAdmin:** set this to the exact Railway `ADMIN_API_KEY` (same pattern as EaAdmin).
/// Overrides `--dart-define` when non-empty. Do not commit real secrets to a public repo.
const String kRailwayAdminApiKey = '';

String _stripSlash(String s) => s.replaceAll(RegExp(r'/$'), '');

/// Public HTTPS origin of the Node API (viewer app must use the same host).
String get resolvedAdminApiBaseUrl {
  final e = _kApiBaseUrlEnv.trim();
  if (e.isNotEmpty) return _stripSlash(e);
  return _stripSlash(kDefaultAdminApiBaseUrl);
}

/// Sent as header `X-Admin-Key` on every admin request.
String get resolvedBundledAdminApiKey {
  final e = _kAdminApiKeyEnv.trim();
  if (e.isNotEmpty) return e;
  return kRailwayAdminApiKey.trim();
}
