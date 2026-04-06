import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/admin_api_config.dart';
import '../models/app_config.dart';

const _prefsKey = 'supaadmin_app_config_v2';
const _prefsKeyLegacy = 'supaadmin_app_config_v1';
const _prefsApiBase = 'supaadmin_api_base_url';
const _prefsJwt = 'supaadmin_admin_jwt_v1';
const _legacyAdminKey = 'supaadmin_admin_api_key';

const _secureJwtKey = 'supaadmin_jwt_v1';
const _securePasswordKey = 'supaadmin_admin_password_v1';

/// v10 uses KeyStore-backed ciphers; migration from older storage is automatic (`migrateOnAlgorithmChange`).
const FlutterSecureStorage _adminSecureStorage = FlutterSecureStorage();

/// Empty workspace — no demo channels/users; add real data in SupaAdmin or load from API.
AppConfig _emptyProductionConfig() {
  return AppConfig(
    configVersion: 2,
    channels: [],
    carousel: [],
    premiumPackages: [],
    malipoPlans: [],
    liveMatches: [],
    notificationLog: [],
    users: [],
    customerCareWhatsapp: '212600000000',
  );
}

bool _looksLikeBundledDemo(AppConfig c) {
  if (c.users.any((u) => u.id.startsWith('usr_demo'))) return true;
  if (c.channels.isNotEmpty &&
      c.channels.length == 12 &&
      c.channels.first.name == 'Vero Sports HD') {
    return true;
  }
  return false;
}

class AdminStore extends ChangeNotifier {
  AdminStore() {
    _config = _emptyProductionConfig();
  }

  late AppConfig _config;
  bool _loaded = false;
  bool get isLoaded => _loaded;

  String? _apiBaseUrlPrefs;
  String? _jwtPrefs;
  String? _lastSyncError;
  bool _syncing = false;

  AppConfig get config => _config;

  String? get lastSyncError => _lastSyncError;

  bool get syncingToServer => _syncing;

  /// JWT and/or bundled `ADMIN_API_KEY` (EaAdmin-style `X-Admin-Key`).
  bool get hasAdminSession =>
      resolvedAdminToken.isNotEmpty || resolvedBundledAdminApiKey.isNotEmpty;

  /// Same value as Railway `ADMIN_API_KEY` when set via dart-define or [admin_api_config].
  String get resolvedAdminApiKey => resolvedBundledAdminApiKey;

  @Deprecated('Use hasAdminSession')
  bool get hasAdminApiKey => hasAdminSession;

  String get resolvedApiBaseUrl {
    final o = _apiBaseUrlPrefs?.trim();
    if (o != null && o.isNotEmpty) return o;
    final e = adminApiBaseUrlFromEnvironment;
    if (e.isNotEmpty) return e;
    return kDefaultAdminApiBaseUrl;
  }

  String get resolvedAdminToken {
    final o = _jwtPrefs?.trim();
    if (o != null && o.isNotEmpty) return o;
    return '';
  }

  Future<void> _clearJwtSession() async {
    try {
      await _adminSecureStorage.delete(key: _secureJwtKey);
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefsJwt);
    _jwtPrefs = null;
  }

  Future<String?> _readJwtWithMigration() async {
    try {
      var t = await _adminSecureStorage.read(key: _secureJwtKey);
      t = t?.trim();
      if (t != null && t.isNotEmpty) return t;
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    final legacy = p.getString(_prefsJwt)?.trim();
    if (legacy != null && legacy.isNotEmpty) {
      try {
        await _adminSecureStorage.write(key: _secureJwtKey, value: legacy);
        await p.remove(_prefsJwt);
      } catch (_) {
        /* keep legacy in prefs */
      }
      return legacy;
    }
    return null;
  }

  Future<void> _persistJwt(String token) async {
    final t = token.trim();
    try {
      await _adminSecureStorage.write(key: _secureJwtKey, value: t);
      final p = await SharedPreferences.getInstance();
      await p.remove(_prefsJwt);
    } catch (_) {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsJwt, t);
    }
    _jwtPrefs = t;
  }

  /// Filled into Settings after load. Updated on each successful sign-in. Not cleared on sign-out.
  Future<String?> readSavedAdminPassword() async {
    try {
      final s = await _adminSecureStorage.read(key: _securePasswordKey);
      if (s == null || s.isEmpty) return null;
      return s;
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _authHeaders({String contentType = ''}) {
    final h = <String, String>{
      'Accept': 'application/json',
      if (contentType.isNotEmpty) 'Content-Type': contentType,
    };
    final key = resolvedBundledAdminApiKey;
    if (key.isNotEmpty) {
      h['X-Admin-Key'] = key;
    }
    final t = resolvedAdminToken;
    if (t.isNotEmpty) {
      h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

  /// Persists API base URL only (no secrets).
  Future<void> saveApiBaseUrl(String apiBaseUrl) async {
    final p = await SharedPreferences.getInstance();
    final b = apiBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    await p.setString(_prefsApiBase, b);
    _apiBaseUrlPrefs = b;
    notifyListeners();
  }

  /// Signs in with [password] (server env `ADMIN_APP_PASSWORD`), stores JWT + remembers password securely, then pulls config.
  Future<void> loginWithPassword(String password) async {
    final base = resolvedApiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/api/v1/auth/admin-login');
    _lastSyncError = null;
    notifyListeners();
    try {
      final res = await http
          .post(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'password': password}),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 503) {
        _lastSyncError =
            'Server not ready: set ADMIN_APP_PASSWORD and JWT_SECRET on the Railway API service.';
        notifyListeners();
        return;
      }
      if (res.statusCode == 401) {
        _lastSyncError = 'Wrong password.';
        notifyListeners();
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _lastSyncError =
            'Sign-in failed (${res.statusCode}): ${res.body.length > 160 ? '${res.body.substring(0, 160)}…' : res.body}';
        notifyListeners();
        return;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        _lastSyncError = 'Invalid sign-in response';
        notifyListeners();
        return;
      }
      final token = decoded['token'] as String?;
      if (token == null || token.isEmpty) {
        _lastSyncError = 'Server did not return a token';
        notifyListeners();
        return;
      }
      await _persistJwt(token);
      try {
        await _adminSecureStorage.write(key: _securePasswordKey, value: password);
      } catch (_) {}
      notifyListeners();
      await pullConfigFromServer();
    } catch (e) {
      _lastSyncError = 'Sign-in failed: $e';
      notifyListeners();
    }
  }

  /// Saves URL then signs in (one step from Settings).
  Future<void> saveUrlAndSignIn({required String apiBaseUrl, required String password}) async {
    await saveApiBaseUrl(apiBaseUrl);
    await loginWithPassword(password);
  }

  Future<void> logout() async {
    await _clearJwtSession();
    _lastSyncError = null;
    notifyListeners();
  }

  @Deprecated('Use logout')
  Future<void> clearSavedAdminKey() => logout();

  Future<void> syncNowToServer() async {
    await _pushConfigToServer();
  }

  Future<String?> testApiUrlReachable() async {
    final base = resolvedApiBaseUrl.replaceAll(RegExp(r'/$'), '');
    try {
      final r = await http
          .get(
            Uri.parse('$base/api/v1/health'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode >= 200 && r.statusCode < 300) return null;
      return 'Health check returned HTTP ${r.statusCode}';
    } catch (e) {
      return 'Cannot reach $base — $e';
    }
  }

  /// Public `GET /api/v1/health/db` — same idea as EaMax `/health/db` for Railway troubleshooting.
  Future<String?> testDatabaseReachable() async {
    final base = resolvedApiBaseUrl.replaceAll(RegExp(r'/$'), '');
    try {
      final r = await http
          .get(
            Uri.parse('$base/api/v1/health/db'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        try {
          final j = jsonDecode(r.body);
          if (j is Map && j['ok'] == true && j['database'] == 'connected') {
            return null;
          }
          return r.body.length > 200 ? '${r.body.substring(0, 200)}…' : r.body;
        } catch (_) {
          return 'Unexpected response body';
        }
      }
      return 'Database check HTTP ${r.statusCode}: ${r.body.length > 160 ? '${r.body.substring(0, 160)}…' : r.body}';
    } catch (e) {
      return 'Cannot reach database endpoint — $e';
    }
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _apiBaseUrlPrefs = p.getString(_prefsApiBase);
    _jwtPrefs = await _readJwtWithMigration();
    await p.remove(_legacyAdminKey);

    var raw = p.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      raw = p.getString(_prefsKeyLegacy);
    }

    if (raw != null && raw.isNotEmpty) {
      try {
        final parsed = AppConfig.fromJsonString(raw);
        if (_looksLikeBundledDemo(parsed)) {
          _config = _emptyProductionConfig();
        } else {
          _config = parsed;
          if (_config.configVersion < 2) {
            _config.configVersion = 2;
          }
        }
      } catch (_) {
        _config = _emptyProductionConfig();
      }
    } else {
      _config = _emptyProductionConfig();
    }

    await p.setString(_prefsKey, _config.toJsonString());
    await p.remove(_prefsKeyLegacy);

    _loaded = true;
    notifyListeners();
    // EaAdmin-style: bundled admin key → always refresh from Postgres on launch.
    if (resolvedBundledAdminApiKey.isNotEmpty) {
      await pullConfigFromServer();
    }
  }

  Future<void> pullConfigFromServer() async {
    if (resolvedAdminToken.isEmpty && resolvedBundledAdminApiKey.isEmpty) {
      return;
    }
    final base = resolvedApiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/api/v1/admin/export').replace(
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
    );
    try {
      final res = await http
          .get(
            uri,
            headers: {
              ..._authHeaders(),
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 40));
      if (res.statusCode == 401 || res.statusCode == 403) {
        if (resolvedAdminToken.isNotEmpty) {
          await _clearJwtSession();
        }
        _lastSyncError = resolvedBundledAdminApiKey.isNotEmpty
            ? 'Unauthorized — ADMIN_API_KEY in this app must match Railway ADMIN_API_KEY.'
            : 'Session expired. Sign in again (Advanced → JWT) or set ADMIN_API_KEY on server and rebuild app.';
        notifyListeners();
        return;
      }
      if (res.statusCode == 503) {
        _lastSyncError =
            'API unavailable (503). On Railway set DATABASE_URL and ADMIN_API_KEY (or JWT_SECRET + ADMIN_APP_PASSWORD).';
        notifyListeners();
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _lastSyncError = 'Load failed (${res.statusCode}): ${res.body.length > 180 ? '${res.body.substring(0, 180)}…' : res.body}';
        notifyListeners();
        return;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        _lastSyncError = 'Server did not return a JSON object.';
        notifyListeners();
        return;
      }
      final j = Map<String, dynamic>.from(decoded);
      if (j['ok'] != true) {
        _lastSyncError = 'Invalid export response (ok != true)';
        notifyListeners();
        return;
      }
      j.remove('ok');
      j.remove('configSyncedAt');
      try {
        _config = AppConfig.fromJson(j);
      } catch (e, st) {
        _lastSyncError = 'Could not parse server config: $e';
        assert(() {
          debugPrint('AppConfig.fromJson failed: $e\n$st');
          return true;
        }());
        notifyListeners();
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _config.toJsonString());
      _lastSyncError = null;
      notifyListeners();
    } catch (e) {
      _lastSyncError = 'Could not load from server: $e';
      notifyListeners();
    }
  }

  Future<void> refreshUsersFromServer() => pullConfigFromServer();

  Future<void> _pushConfigToServer() async {
    if (resolvedAdminToken.isEmpty && resolvedBundledAdminApiKey.isEmpty) {
      _lastSyncError =
          'Sync needs ADMIN_API_KEY: set it on Railway, then rebuild SupaAdmin with '
          '--dart-define=ADMIN_API_KEY=… or set kOptionalInSourceAdminApiKey in admin_api_config.dart.';
      notifyListeners();
      return;
    }
    final base = resolvedApiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/api/v1/admin/import');
    _syncing = true;
    _lastSyncError = null;
    notifyListeners();
    try {
      final res = await http
          .post(
            uri,
            headers: {
              ..._authHeaders(contentType: 'application/json'),
              'Cache-Control': 'no-cache',
            },
            body: jsonEncode(_config.toJson()),
          )
          .timeout(const Duration(seconds: 45));
      if (res.statusCode == 401 || res.statusCode == 403) {
        if (resolvedAdminToken.isNotEmpty) {
          await _clearJwtSession();
        }
        _lastSyncError = resolvedBundledAdminApiKey.isNotEmpty
            ? 'Unauthorized — check ADMIN_API_KEY matches Railway.'
            : 'Session expired. Sign in again.';
      } else if (res.statusCode == 503) {
        _lastSyncError =
            'Database unavailable (503). Check Railway DATABASE_URL and admin env vars.';
      } else if (res.statusCode >= 200 && res.statusCode < 300) {
        _lastSyncError = null;
      } else {
        _lastSyncError = 'Sync failed (${res.statusCode}): ${res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body}';
      }
    } catch (e) {
      _lastSyncError = 'Sync failed: $e';
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, _config.toJsonString());
    notifyListeners();
    await _pushConfigToServer();
  }

  Future<void> replaceConfig(AppConfig next) async {
    _config = next;
    await _persist();
  }

  Future<void> resetToDefaults() async {
    _config = _emptyProductionConfig();
    await _persist();
  }

  Future<void> setCustomerCareWhatsapp(String raw) async {
    _config.customerCareWhatsapp = normalizeCustomerCareWhatsapp(raw);
    await _persist();
  }

  Future<void> upsertChannel(ChannelDto c) async {
    final i = _config.channels.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      _config.channels[i] = c;
    } else {
      _config.channels.add(c);
    }
    await _persist();
  }

  Future<void> deleteChannel(int id) async {
    _config.channels.removeWhere((c) => c.id == id);
    await _persist();
  }

  Future<void> reorderChannels(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _config.channels.removeAt(oldIndex);
    _config.channels.insert(newIndex, item);
    await _persist();
  }

  int nextChannelId() {
    if (_config.channels.isEmpty) return 0;
    return _config.channels.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> upsertCarousel(int index, CarouselDto slide) async {
    if (index >= 0 && index < _config.carousel.length) {
      _config.carousel[index] = slide;
    } else {
      _config.carousel.add(slide);
    }
    await _persist();
  }

  Future<void> removeCarouselAt(int index) async {
    if (index >= 0 && index < _config.carousel.length) {
      _config.carousel.removeAt(index);
      await _persist();
    }
  }

  Future<void> addCarousel(CarouselDto slide) async {
    _config.carousel.add(slide);
    await _persist();
  }

  Future<void> reorderCarousel(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _config.carousel.removeAt(oldIndex);
    _config.carousel.insert(newIndex, item);
    await _persist();
  }

  Future<void> upsertPackage(PackageDto p) async {
    final i = _config.premiumPackages.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      _config.premiumPackages[i] = p;
    } else {
      _config.premiumPackages.add(p);
    }
    await _persist();
  }

  Future<void> deletePackage(String id) async {
    _config.premiumPackages.removeWhere((p) => p.id == id);
    await _persist();
  }

  Future<void> upsertMalipo(MalipoPlanDto m) async {
    final i = _config.malipoPlans.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      _config.malipoPlans[i] = m;
    } else {
      _config.malipoPlans.add(m);
    }
    await _persist();
  }

  Future<void> deleteMalipo(String id) async {
    _config.malipoPlans.removeWhere((m) => m.id == id);
    await _persist();
  }

  Future<void> upsertLive(LiveMatchDto m) async {
    final i = _config.liveMatches.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      _config.liveMatches[i] = m;
    } else {
      _config.liveMatches.add(m);
      _config.liveMatches.sort((a, b) => a.id.compareTo(b.id));
    }
    await _persist();
  }

  Future<void> deleteLive(int id) async {
    _config.liveMatches.removeWhere((m) => m.id == id);
    await _persist();
  }

  int nextLiveId() {
    if (_config.liveMatches.isEmpty) return 0;
    return _config.liveMatches.map((m) => m.id).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> sendNotification({required String title, required String body, required String target}) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _config.notificationLog.insert(
      0,
      NotificationEntryDto(
        id: id,
        title: title,
        body: body,
        target: target,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    await _persist();
  }

  Future<void> deleteNotification(String id) async {
    _config.notificationLog.removeWhere((n) => n.id == id);
    await _persist();
  }

  Future<void> upsertUser(UserDto u) async {
    final i = _config.users.indexWhere((x) => x.id == u.id);
    if (i >= 0) {
      _config.users[i] = u;
    } else {
      _config.users.add(u);
    }
    await _persist();
  }

  Future<void> deleteUser(String id) async {
    if (resolvedAdminToken.isNotEmpty || resolvedBundledAdminApiKey.isNotEmpty) {
      final base = resolvedApiBaseUrl.replaceAll(RegExp(r'/$'), '');
      final uri = Uri.parse('$base/api/v1/admin/users/${Uri.encodeComponent(id)}');
      try {
        await http
            .delete(
              uri,
              headers: _authHeaders(),
            )
            .timeout(const Duration(seconds: 25));
      } catch (_) {}
    }
    _config.users.removeWhere((u) => u.id == id);
    await _persist();
  }

  Future<void> addUserPremiumDuration(String userId, Duration duration) async {
    final i = _config.users.indexWhere((x) => x.id == userId);
    if (i < 0) return;
    final u = _config.users[i];
    final now = DateTime.now();
    var start = now;
    final existing = u.premiumUntilMs;
    if (existing != null) {
      final ex = DateTime.fromMillisecondsSinceEpoch(existing);
      if (ex.isAfter(now)) start = ex;
    }
    final end = start.add(duration);
    _config.users[i] = u.copyWith(premiumUntilMs: end.millisecondsSinceEpoch);
    await _persist();
  }

  Future<void> setUserPremiumUntil(String userId, DateTime? endUtc) async {
    final i = _config.users.indexWhere((x) => x.id == userId);
    if (i < 0) return;
    final u = _config.users[i];
    _config.users[i] = endUtc == null
        ? u.copyWith(clearPremiumUntilMs: true)
        : u.copyWith(premiumUntilMs: endUtc.millisecondsSinceEpoch);
    await _persist();
  }

  Future<void> importJson(String raw) async {
    final next = AppConfig.fromJsonString(raw);
    await replaceConfig(next);
  }
}
