/// Build-time defaults for SupaAdmin. Runtime overrides live in SharedPreferences (Settings).

const String kDefaultAdminApiBaseUrl = 'https://supasokatv-production.up.railway.app';

const String _kApiBaseUrlEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');

String _stripSlash(String s) => s.replaceAll(RegExp(r'/$'), '');

String get apiBaseUrlFromBuild {
  final e = _kApiBaseUrlEnv.trim();
  if (e.isNotEmpty) return _stripSlash(e);
  return _stripSlash(kDefaultAdminApiBaseUrl);
}
