import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../admin_messenger.dart';
import '../config/admin_api_config.dart';
import '../models/app_config.dart';

const _prefsKey = 'supaadmin_app_config_v2';
const _prefsKeyLegacy = 'supaadmin_app_config_v1';
const _prefsJwt = 'supaadmin_jwt_v1';

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

  String _jwt = '';

  String? _lastSyncError;
  bool _syncing = false;

  AppConfig get config => _config;

  String? get lastSyncError => _lastSyncError;

  bool get syncingToServer => _syncing;

  /// Non-empty when key was compiled in (`kRailwayAdminApiKey` / `--dart-define=ADMIN_API_KEY=…`).
  bool get adminApiKeyIsFromBuild => false;

  /// Runtime prefs only — never exposes a build-time key (for Settings field).
  String get runtimeAdminApiKeyForEditing => _jwt;

  /// JWT token for auth.
  String get resolvedAdminApiKey => _jwt.trim();

  String get resolvedApiBaseUrl => apiBaseUrlFromBuild;

  bool get hasAdminSession => resolvedAdminApiKey.isNotEmpty;

  @Deprecated('Use hasAdminSession')
  bool get hasAdminApiKey => hasAdminSession;

  void _snack(String message) {
    final m = adminScaffoldMessengerKey.currentState;
    if (m == null) return;
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, String> _authHeaders({String contentType = ''}) {
    final key = resolvedAdminApiKey;
    return {
      'Accept': 'application/json',
      if (contentType.isNotEmpty) 'Content-Type': contentType,
      if (key.isNotEmpty) 'Authorization': 'Bearer $key',
    };
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('supaadmin_admin_jwt_v1');

    var jwt = p.getString(_prefsJwt);
    if (jwt == null || jwt.isEmpty) {
      // Migrate old API key to JWT if possible, but since we can't, just clear
    }

    _jwt = (jwt ?? '').trim();

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

    if (hasAdminSession) {
      await pullConfigFromServer();
    }
  }

  Future<String?> login(String password) async {
    final base = resolvedApiBaseUrl;
    final uri = Uri.parse('$base/api/v1/auth/admin-login');
    try {
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'password': password}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['ok'] == true && decoded['token'] is String) {
          final token = decoded['token'] as String;
          await saveRuntimeSyncSettings(jwt: token);
          return null; // success
        }
      }
      return 'Login failed: ${res.statusCode} ${res.body}';
    } catch (e) {
      return 'Login error: $e';
    }
  }

  Future<void> logout() async {
    await saveRuntimeSyncSettings(jwt: '');
  }

  Future<void> saveRuntimeSyncSettings({
    required String jwt,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (jwt.isEmpty) {
      await prefs.remove(_prefsJwt);
      _jwt = '';
    } else {
      await prefs.setString(_prefsJwt, jwt);
      _jwt = jwt;
    }

    notifyListeners();
    if (hasAdminSession) {
      await pullConfigFromServer();
    }
  }

  Future<void> pullConfigFromServer() async {
    if (!hasAdminSession) {
      return;
    }
    final base = resolvedApiBaseUrl;
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
        _lastSyncError =
            'Unauthorized — password si sahihi; ingia tena.';
        notifyListeners();
        return;
      }
      if (res.statusCode == 503) {
        _lastSyncError = 'API unavailable (503). Set DATABASE_URL and ADMIN_APP_PASSWORD on Railway.';
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

  /// Ensures viewer accounts from `POST /public/register-user` are in the next import payload.
  Future<void> _mergeRegisteredUsersFromApi() async {
    if (!hasAdminSession) return;
    final base = resolvedApiBaseUrl;
    final uri = Uri.parse('$base/api/v1/admin/users').replace(
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
    );
    try {
      final r = await http
          .get(
            uri,
            headers: {
              ..._authHeaders(),
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 22));
      if (r.statusCode < 200 || r.statusCode >= 300) return;
      final decoded = jsonDecode(r.body);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['ok'] != true) return;
      final list = decoded['users'];
      if (list is! List<dynamic>) return;
      final seen = _config.users.map((u) => u.id).toSet();
      for (final raw in list) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final id = '${m['id'] ?? ''}'.trim();
        if (id.isEmpty || seen.contains(id)) continue;
        _config.users.add(UserDto.fromJson(m));
        seen.add(id);
      }
    } catch (_) {}
  }

  /// Public sync method to push all changes to server.
  Future<void> syncToServer() async {
    await _pushConfigToServer();
  }

  Future<void> _pushConfigToServer() async {
    if (!hasAdminSession) {
      _lastSyncError =
          'Hakuna JWT — ingia tena kwenye Settings';
      notifyListeners();
      _snack(_lastSyncError!);
      return;
    }
    final base = resolvedApiBaseUrl;
    final uri = Uri.parse('$base/api/v1/admin/import');
    _syncing = true;
    _lastSyncError = null;
    notifyListeners();

    Object? lastErr;
    http.Response? res;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        res = await http
            .post(
              uri,
              headers: {
                ..._authHeaders(contentType: 'application/json'),
                'Cache-Control': 'no-cache',
              },
              body: jsonEncode(_config.toJson()),
            )
            .timeout(const Duration(seconds: 45));
        break;
      } catch (e) {
        lastErr = e;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 400 * (1 << attempt)));
        }
      }
    }

    try {
      if (res == null) {
        _lastSyncError = 'Sync failed: $lastErr';
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        _lastSyncError = 'Unauthorized — login again with your admin password.';
      } else if (res.statusCode == 503) {
        _lastSyncError = 'Database unavailable (503). Check Railway DATABASE_URL.';
      } else if (res.statusCode >= 200 && res.statusCode < 300) {
        _lastSyncError = null;
      } else {
        _lastSyncError = 'Sync failed (${res.statusCode}): ${res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body}';
      }
    } finally {
      _syncing = false;
      notifyListeners();
      if (_lastSyncError != null && _lastSyncError!.isNotEmpty) {
        _snack(_lastSyncError!);
      }
    }
  }

  Future<void> _persist() async {
    if (hasAdminSession) {
      await _mergeRegisteredUsersFromApi();
    }
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
    if (hasAdminSession) {
      final base = resolvedApiBaseUrl;
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
