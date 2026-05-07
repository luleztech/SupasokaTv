// Build-time defaults for SupaAdmin. Runtime overrides live in SharedPreferences (Settings).

const String kDefaultAdminApiBaseUrl = 'https://supasokatv-production.up.railway.app';

const String _kApiBaseUrlEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');

String _stripSlash(String s) => s.replaceAll(RegExp(r'/$'), '');
String _sanitizeBaseUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  // Guard against malformed dart-define values like `uri+https://host`.
  s = s.replaceFirst(RegExp(r'^uri\+'), '');
  // Also handle accidental `uri:https://...` / `uri://https://...` prefixes.
  s = s.replaceFirst(RegExp(r'^uri:(//)?'), '');
  return _stripSlash(s);
}

String get apiBaseUrlFromBuild {
  final e = _sanitizeBaseUrl(_kApiBaseUrlEnv);
  if (e.isNotEmpty) return e;
  return _sanitizeBaseUrl(kDefaultAdminApiBaseUrl);
}
