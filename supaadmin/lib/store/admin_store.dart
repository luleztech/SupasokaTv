import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../admin_messenger.dart' show adminFormatError, adminScaffoldMessengerKey;
import '../config/admin_api_config.dart';
import '../models/app_config.dart';

const _prefsKey = 'supaadmin_app_config_v2';
const _prefsKeyLegacy = 'supaadmin_app_config_v1';
const _prefsJwt = 'supaadmin_jwt_v1';
const _prefsKeyAppUpdate = 'supaadmin_app_update_policy_v1';

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

Map<String, dynamic> _appUpdateSnapshot(AppConfig c) => {
      'forceUpdateEnabled': c.forceUpdateEnabled,
      'minAndroidBuild': c.minAndroidBuild,
      'minAndroidVersion': c.minAndroidVersion,
      'latestAndroidVersion': c.latestAndroidVersion,
      'latestAndroidBuild': c.latestAndroidBuild,
      'playStoreUrl': c.playStoreUrl,
    };

bool _appUpdateIsMeaningful(Map<String, dynamic> m) {
  if (m['forceUpdateEnabled'] == true) return true;
  if (((m['minAndroidBuild'] as num?)?.toInt() ?? 0) > 0) return true;
  if ((m['minAndroidVersion'] as String? ?? '').trim().isNotEmpty) return true;
  if ((m['latestAndroidVersion'] as String? ?? '').trim().isNotEmpty) return true;
  if (((m['latestAndroidBuild'] as num?)?.toInt() ?? 0) > 0) return true;
  return false;
}

void _applyAppUpdateSnapshot(AppConfig c, Map<String, dynamic> m) {
  c.forceUpdateEnabled = m['forceUpdateEnabled'] == true;
  c.minAndroidBuild = (m['minAndroidBuild'] as num?)?.toInt() ?? 0;
  c.minAndroidVersion = (m['minAndroidVersion'] as String? ?? '').trim();
  c.latestAndroidVersion = (m['latestAndroidVersion'] as String? ?? '').trim();
  c.latestAndroidBuild = (m['latestAndroidBuild'] as num?)?.toInt() ?? 0;
  final url = (m['playStoreUrl'] as String? ?? '').trim();
  if (url.isNotEmpty) c.playStoreUrl = url;
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
  bool _savingAppUpdatePolicy = false;
  Timer? _syncRetryTimer;
  Map<String, int> _paymentHealthSummary = const {};
  List<Map<String, String?>> _paymentHealthRecent = const [];
  List<Map<String, String?>> _paymentDailyRevenue = const [];
  String _revenueTodayDay = '';
  bool _loadingPaymentHealth = false;

  String _paymentProvider = 'zeno';
  bool? _paymentProviderConfigured;
  bool? _zenoConfigured;
  bool? _sonicConfigured;
  bool? _paymentProviderApiReady;
  String? _paymentProviderStatusHint;
  bool? _loadingPaymentProvider;
  bool? _savingPaymentProvider;

  AppConfig get config => _config;

  String? get lastSyncError => _lastSyncError;

  bool get syncingToServer => _syncing;
  bool get savingAppUpdatePolicy => _savingAppUpdatePolicy;
  Map<String, int> get paymentHealthSummary => _paymentHealthSummary;
  List<Map<String, String?>> get paymentHealthRecent => _paymentHealthRecent;
  List<Map<String, String?>> get paymentDailyRevenue => _paymentDailyRevenue;
  String get revenueTodayDay => _revenueTodayDay;
  bool get loadingPaymentHealth => _loadingPaymentHealth;

  String get paymentProvider => _paymentProvider;
  bool get paymentProviderConfigured => _paymentProviderConfigured ?? false;
  bool get zenoConfigured => _zenoConfigured ?? false;
  bool get sonicConfigured => _sonicConfigured ?? false;
  bool get loadingPaymentProvider => _loadingPaymentProvider ?? false;
  bool get savingPaymentProvider => _savingPaymentProvider ?? false;
  bool get paymentProviderApiReady => _paymentProviderApiReady ?? false;
  String? get paymentProviderStatusHint => _paymentProviderStatusHint;

  static bool _jsonBool(dynamic v) => v == true || v == 'true' || v == 1;

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

  Future<Map<String, dynamic>?> _readAppUpdatePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyAppUpdate);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      await prefs.remove(_prefsKeyAppUpdate);
      return null;
    }
  }

  Future<void> _writeAppUpdatePrefs(AppConfig c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyAppUpdate, jsonEncode(_appUpdateSnapshot(c)));
  }

  Future<void> _overlayAppUpdateFromPrefs() async {
    final saved = await _readAppUpdatePrefs();
    if (saved != null && _appUpdateIsMeaningful(saved)) {
      _applyAppUpdateSnapshot(_config, saved);
    }
  }

  Future<bool> _pushAppUpdatePolicyToServer() async {
    if (!hasAdminSession) return false;

    final base = resolvedApiBaseUrl;
    final uri = Uri.parse('$base/api/v1/admin/settings/app-update');
    final headers = _authHeaders(contentType: 'application/json');
    final body = jsonEncode(_appUpdateSnapshot(_config));

    Future<http.Response> sendPut() =>
        http.put(uri, headers: headers, body: body).timeout(const Duration(seconds: 20));
    Future<http.Response> sendPost() =>
        http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 20));

    for (final send in [sendPut, sendPost]) {
      try {
        final res = await send();
        if (res.statusCode >= 200 && res.statusCode < 300) {
          _lastSyncError = null;
          return true;
        }
        if (res.statusCode != 404 && res.statusCode != 405) {
          _lastSyncError =
              'Update policy save failed (${res.statusCode}): ${res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body}';
          return false;
        }
      } catch (e) {
        _lastSyncError = 'Update policy save failed: $e';
        return false;
      }
    }

    await _pushConfigToServer();
    return _lastSyncError == null || _lastSyncError!.isEmpty;
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

    await _overlayAppUpdateFromPrefs();

    await p.setString(_prefsKey, _config.toJsonString());
    await _writeAppUpdatePrefs(_config);
    await p.remove(_prefsKeyLegacy);

    _loaded = true;
    notifyListeners();

    if (hasAdminSession) {
      await pullConfigFromServer();
      await Future.wait([refreshPaymentHealth(), refreshPaymentProvider()]);
    }
    _ensureAutoSyncRetryLoop();
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
      await Future.wait([refreshPaymentHealth(), refreshPaymentProvider()]);
    }
    _ensureAutoSyncRetryLoop();
  }

  @override
  void dispose() {
    _syncRetryTimer?.cancel();
    super.dispose();
  }

  void _ensureAutoSyncRetryLoop() {
    _syncRetryTimer?.cancel();
    if (!hasAdminSession) return;
    _syncRetryTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!hasAdminSession || _syncing) return;
      if (_lastSyncError == null || _lastSyncError!.isEmpty) return;
      _pushConfigToServer();
    });
  }

  void _normalizeConfigForServer() {
    final validChannelIds = _config.channels.map((c) => c.id).toSet();
    _config.carousel.removeWhere((s) => !validChannelIds.contains(s.channelId));
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
      final beforePull = _appUpdateSnapshot(_config);
      final savedPrefs = await _readAppUpdatePrefs();
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

      final fromServer = _appUpdateSnapshot(_config);
      if (_appUpdateIsMeaningful(fromServer)) {
        _applyAppUpdateSnapshot(_config, fromServer);
      } else {
        final keep = savedPrefs ?? beforePull;
        if (_appUpdateIsMeaningful(keep)) {
          _applyAppUpdateSnapshot(_config, keep);
          unawaited(_pushAppUpdatePolicyToServer());
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _config.toJsonString());
      await _writeAppUpdatePrefs(_config);
      _lastSyncError = null;
      notifyListeners();
    } catch (e) {
      _lastSyncError = 'Could not load from server: $e';
      notifyListeners();
    }
  }

  Future<void> refreshUsersFromServer() => pullConfigFromServer();

  Future<void> refreshPaymentProvider() async {
    if (!hasAdminSession) return;
    _loadingPaymentProvider = true;
    notifyListeners();
    try {
      final base = resolvedApiBaseUrl;
      final uri = Uri.parse('$base/api/v1/admin/settings/payment-provider').replace(
        queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
      );
      final res = await http
          .get(uri, headers: {..._authHeaders(), 'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 18));
      if (res.statusCode == 404) {
        _paymentProviderApiReady = false;
        _paymentProviderStatusHint =
            'Backend haijasasishwa: deploy API mpya kwenye Railway (payment-provider routes).';
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _paymentProviderApiReady = false;
        _paymentProviderStatusHint = 'Haikuweza kusoma mipangilio ya malipo (HTTP ${res.statusCode}).';
        return;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return;
      _paymentProviderApiReady = true;
      _paymentProviderStatusHint = null;
      _paymentProvider = (decoded['paymentProvider'] ?? 'zeno').toString();
      _paymentProviderConfigured = _jsonBool(decoded['configured']);
      _zenoConfigured = _jsonBool(decoded['zenoConfigured']);
      _sonicConfigured = _jsonBool(decoded['sonicConfigured']);
    } catch (_) {
      _paymentProviderApiReady = false;
      _paymentProviderStatusHint = 'Mtandao au seva haikupatikana.';
    } finally {
      _loadingPaymentProvider = false;
      notifyListeners();
    }
  }

  Future<bool> updatePaymentProvider(String next) async {
    if (!hasAdminSession || (savingPaymentProvider)) return false;
    final normalized = next.toLowerCase() == 'sonicpesa' ? 'sonicpesa' : 'zeno';
    if (!paymentProviderApiReady) {
      _snack(
        _paymentProviderStatusHint ??
            'Backend haijasasishwa. Deploy Supasoka API kwenye Railway kisha jaribu tena.',
      );
      return false;
    }
    if (normalized == 'sonicpesa' && !sonicConfigured) {
      _snack(
        'SONICPESA_API_KEY haipo kwenye Supasoka Railway. Nakili kutoka EaMax → Variables, kisha Redeploy.',
      );
      return false;
    }
    if (normalized == 'zeno' && !zenoConfigured) {
      _snack('ZENO_API_KEY haipo kwenye Supasoka Railway. Weka key kisha Redeploy.');
      return false;
    }
    if (normalized == _paymentProvider) return true;
    final previous = _paymentProvider;
    _paymentProvider = normalized;
    _savingPaymentProvider = true;
    notifyListeners();
    try {
      final base = resolvedApiBaseUrl;
      final uri = Uri.parse('$base/api/v1/admin/settings/payment-provider');
      final res = await http
          .put(
            uri,
            headers: _authHeaders(contentType: 'application/json'),
            body: jsonEncode({'paymentProvider': normalized}),
          )
          .timeout(const Duration(seconds: 22));
      Map<String, dynamic>? decoded;
      try {
        decoded = jsonDecode(res.body) as Map<String, dynamic>?;
      } catch (_) {}
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _paymentProvider = previous;
        final err = decoded?['error'];
        final msg = err is Map
            ? (err['message'] ?? err['code'])?.toString()
            : decoded?['error']?.toString();
        _snack(msg?.isNotEmpty == true ? msg! : 'Could not update payment provider (${res.statusCode})');
        return false;
      }
      _paymentProvider = (decoded?['paymentProvider'] ?? normalized).toString();
      _paymentProviderConfigured = decoded?['configured'] != false;
      await refreshPaymentProvider();
      _snack(
        normalized == 'sonicpesa'
            ? 'SonicPesa — malipo mapya yanaenda kwenye akaunti yako ya SonicPesa (sawa na EaMax).'
            : 'ZenoPay — malipo mapya yanaenda kwenye ZenoPay.',
      );
      return true;
    } catch (e) {
      _paymentProvider = previous;
      _snack('Could not update payment provider: $e');
      return false;
    } finally {
      _savingPaymentProvider = false;
      notifyListeners();
    }
  }

  Future<void> refreshPaymentHealth() async {
    if (!hasAdminSession) return;
    _loadingPaymentHealth = true;
    notifyListeners();
    try {
      final base = resolvedApiBaseUrl;
      final uri = Uri.parse('$base/api/v1/admin/payment-health').replace(
        queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
      );
      final res = await http
          .get(
            uri,
            headers: {
              ..._authHeaders(),
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        return;
      }
      final summaryRaw = decoded['summary'];
      if (summaryRaw is Map) {
        _paymentHealthSummary = {
          for (final e in summaryRaw.entries)
            e.key.toString(): int.tryParse('${e.value}') ?? 0,
        };
      }
      final recentRaw = decoded['recent'];
      if (recentRaw is List) {
        _paymentHealthRecent = recentRaw
            .whereType<Map>()
            .map(
              (r) => <String, String?>{
                'orderId': r['orderId']?.toString(),
                'publicId': r['publicId']?.toString(),
                'planId': r['planId']?.toString(),
                'amountTzs': r['amountTzs']?.toString(),
                'status': r['status']?.toString(),
                'createdAt': r['createdAt']?.toString(),
              },
            )
            .toList(growable: false);
      }
      final dailyRaw = decoded['dailyRevenue'];
      if (dailyRaw is List) {
        _paymentDailyRevenue = dailyRaw
            .whereType<Map>()
            .map(
              (r) => <String, String?>{
                'day': r['day']?.toString(),
                'count': r['count']?.toString(),
                'totalTzs': r['totalTzs']?.toString(),
              },
            )
            .toList(growable: false);
      } else {
        _paymentDailyRevenue = const [];
      }
      _revenueTodayDay = decoded['revenueTodayDay']?.toString() ?? '';
    } catch (_) {
      // Keep dashboard usable even if health endpoint is temporarily unavailable.
    } finally {
      _loadingPaymentHealth = false;
      notifyListeners();
    }
  }

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
    _normalizeConfigForServer();
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
    _normalizeConfigForServer();
    if (hasAdminSession) {
      await _mergeRegisteredUsersFromApi();
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, _config.toJsonString());
    notifyListeners();
    await _pushConfigToServer();
  }

  Future<void> _saveLocalConfigOnly() async {
    _normalizeConfigForServer();
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, _config.toJsonString());
    await _writeAppUpdatePrefs(_config);
    notifyListeners();
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

  Future<void> setAppUpdatePolicy({
    required bool forceUpdateEnabled,
    required int minAndroidBuild,
    required String minAndroidVersion,
    required String latestAndroidVersion,
    required int latestAndroidBuild,
    String? playStoreUrl,
  }) async {
    _config.forceUpdateEnabled = forceUpdateEnabled;
    _config.minAndroidBuild = minAndroidBuild < 0 ? 0 : minAndroidBuild;
    _config.minAndroidVersion = minAndroidVersion.trim();
    _config.latestAndroidVersion = latestAndroidVersion.trim();
    _config.latestAndroidBuild = latestAndroidBuild < 0 ? 0 : latestAndroidBuild;
    final storeUrl = playStoreUrl?.trim() ?? '';
    if (storeUrl.isNotEmpty) {
      _config.playStoreUrl = storeUrl;
    }

    await _writeAppUpdatePrefs(_config);
    await _saveLocalConfigOnly();

    if (!hasAdminSession) return;

    _savingAppUpdatePolicy = true;
    _lastSyncError = null;
    notifyListeners();

    try {
      await _pushAppUpdatePolicyToServer();
    } finally {
      _savingAppUpdatePolicy = false;
      notifyListeners();
      if (_lastSyncError != null && _lastSyncError!.isNotEmpty) {
        _snack(_lastSyncError!);
      }
    }
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

  /// Returns `true` when the server stored a notification row (push history).
  Future<bool> sendNotification({required String title, required String body, required String target}) async {
    if (hasAdminSession) {
      final base = resolvedApiBaseUrl;
      final uri = Uri.parse('$base/api/v1/admin/notify');
      final res = await http
          .post(
            uri,
            headers: _authHeaders(contentType: 'application/json'),
            body: jsonEncode({
              'title': title,
              'body': body,
              'target': target,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        String reason = '';
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map) {
            final err = decoded['error'];
            if (err is String) {
              reason = err;
            } else if (err is Map && err['message'] != null) {
              reason = '${err['message']}';
            }
          }
        } catch (_) {}
        if (reason.trim().isEmpty) {
          reason = 'HTTP ${res.statusCode}';
        }
        throw Exception('Push send failed (${res.statusCode}): $reason');
      }
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final persistFail = decoded['notificationPersistError'] != null &&
              decoded['notificationPersistError'].toString().trim().isNotEmpty;
          final n = decoded['notification'];
          if (n is Map) {
            final entry = NotificationEntryDto.fromJson(Map<String, dynamic>.from(n as Map));
            _config.notificationLog.removeWhere((x) => x.id == entry.id);
            _config.notificationLog.insert(0, entry);
            notifyListeners();
            final p = await SharedPreferences.getInstance();
            await p.setString(_prefsKey, _config.toJsonString());
            return true;
          }
          if (persistFail) {
            return false;
          }
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
          notifyListeners();
          final p = await SharedPreferences.getInstance();
          await p.setString(_prefsKey, _config.toJsonString());
          return false;
        }
      } catch (_) {}
    }
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
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, _config.toJsonString());
    return false;
  }

  Future<String> checkPushHealth() async {
    if (!hasAdminSession) {
      throw Exception('Not logged in. Please login again.');
    }
    final base = resolvedApiBaseUrl;
    final uri = Uri.parse('$base/api/v1/admin/notify-health');
    final res = await http
        .get(
          uri,
          headers: {
            ..._authHeaders(),
            'Cache-Control': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['message'] != null) {
          return '${decoded['message']}';
        }
      } catch (_) {}
      return 'Push configuration looks valid.';
    }
    String reason = '';
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is String) {
          reason = err;
        } else if (err is Map && err['message'] != null) {
          reason = '${err['message']}';
        }
      }
    } catch (_) {}
    if (reason.trim().isEmpty) {
      reason = 'HTTP ${res.statusCode}';
    }
    throw Exception(reason);
  }

  Future<void> sendExpiredReminder(UserDto user) async {
    if (!hasAdminSession) {
      throw Exception('Not logged in. Please login again.');
    }
    final base = resolvedApiBaseUrl;
    final uri = Uri.parse('$base/api/v1/admin/notify-user/${Uri.encodeComponent(user.id)}');
    const title = 'Kifurushi chako kimeisha';
    final body =
        'Mpendwa mteja, kifurushi chako kimeisha muda wake. Tafadhali lipia uendelee kufurahia vipindi vyetu bora sana.';
    final res = await http
        .post(
          uri,
          headers: _authHeaders(contentType: 'application/json'),
          body: jsonEncode({'title': title, 'body': body}),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String reason = '';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final err = decoded['error'];
          if (err is String) {
            reason = err;
          } else if (err is Map && err['message'] != null) {
            reason = '${err['message']}';
          }
        }
      } catch (_) {}
      throw Exception(reason.isEmpty ? 'HTTP ${res.statusCode}' : reason);
    }
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final persistRaw = decoded['notificationPersistError'];
        if (persistRaw != null && persistRaw.toString().trim().isNotEmpty) {
          _snack('Ujumbe umetumwa lakini historia haijahifadhiwa: ${persistRaw.toString().trim()}');
        }
        final n = decoded['notification'];
        if (n is Map) {
          final entry = NotificationEntryDto.fromJson(Map<String, dynamic>.from(n as Map));
          _config.notificationLog.removeWhere((x) => x.id == entry.id);
          _config.notificationLog.insert(0, entry);
          notifyListeners();
          final p = await SharedPreferences.getInstance();
          await p.setString(_prefsKey, _config.toJsonString());
        }
      }
    } catch (_) {}
  }

  /// Sends the standard expired-subscription reminder to many viewers at once (server: `/notify-expired-batch`).
  Future<ExpiredBatchOutcome> sendExpiredRemindersBatch(List<UserDto> users) async {
    if (!hasAdminSession) {
      throw Exception('Not logged in. Please login again.');
    }
    final ids = users.map((u) => u.id.trim()).where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) {
      return ExpiredBatchOutcome(sent: 0, failed: 0);
    }
    const title = 'Kifurushi chako kimeisha';
    const body =
        'Mpendwa mteja, kifurushi chako kimeisha muda wake. Tafadhali lipia uendelee kufurahia vipindi vyetu bora sana.';
    final base = resolvedApiBaseUrl;
    final uri = Uri.parse('$base/api/v1/admin/notify-expired-batch');
    final res = await http
        .post(
          uri,
          headers: _authHeaders(contentType: 'application/json'),
          body: jsonEncode({'ids': ids, 'title': title, 'body': body}),
        )
        .timeout(const Duration(seconds: 120));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String reason = '';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final err = decoded['error'];
          if (err is String) {
            reason = err;
          } else if (err is Map && err['message'] != null) {
            reason = '${err['message']}';
          }
        }
      } catch (_) {}
      throw Exception(reason.isEmpty ? 'HTTP ${res.statusCode}' : reason);
    }
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final persistRaw = decoded['notificationPersistError'];
        if (persistRaw != null && persistRaw.toString().trim().isNotEmpty) {
          _snack('Baadhi ya historia hazijahifadhiwa: ${persistRaw.toString().trim()}');
        }
        final sent = decoded['sent'];
        final failed = decoded['failed'];
        final s = sent is int ? sent : int.tryParse('$sent') ?? 0;
        final f = failed is int ? failed : int.tryParse('$failed') ?? 0;
        return ExpiredBatchOutcome(sent: s, failed: f);
      }
    } catch (_) {}
    return ExpiredBatchOutcome(sent: 0, failed: ids.length);
  }

  Future<void> deleteNotification(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    if (hasAdminSession) {
      final base = resolvedApiBaseUrl;
      final uri = Uri.parse('$base/api/v1/admin/notifications/${Uri.encodeComponent(trimmed)}');
      try {
        final res = await http
            .delete(
              uri,
              headers: _authHeaders(),
            )
            .timeout(const Duration(seconds: 25));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('Delete failed (${res.statusCode})');
        }
      } catch (e) {
        _snack('Delete notification failed: ${adminFormatError(e)}');
        return;
      }
    }
    _config.notificationLog.removeWhere((n) => n.id == trimmed);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, _config.toJsonString());
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
    final next = endUtc == null
        ? u.copyWith(clearPremiumUntilMs: true)
        : u.copyWith(premiumUntilMs: endUtc.millisecondsSinceEpoch);
    _config.users[i] = next;

    // Fast path: single-user premium update, avoids heavy full-config import latency.
    if (hasAdminSession) {
      final base = resolvedApiBaseUrl;
      final uri = Uri.parse('$base/api/v1/admin/users/${Uri.encodeComponent(userId)}/premium');
      _syncing = true;
      _lastSyncError = null;
      notifyListeners();
      try {
        final res = await http
            .put(
              uri,
              headers: _authHeaders(contentType: 'application/json'),
              body: jsonEncode({
                'premiumUntilMs': endUtc?.millisecondsSinceEpoch,
              }),
            )
            .timeout(const Duration(seconds: 20));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          await _saveLocalConfigOnly();
          return;
        }
        _lastSyncError =
            'Premium update failed (${res.statusCode}): ${res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body}';
      } catch (e) {
        _lastSyncError = 'Premium update failed: $e';
      } finally {
        _syncing = false;
        notifyListeners();
        if (_lastSyncError != null && _lastSyncError!.isNotEmpty) {
          _snack(_lastSyncError!);
        }
      }
    }

    // Fallback for older backend versions.
    await _persist();
  }

  Future<void> importJson(String raw) async {
    final next = AppConfig.fromJsonString(raw);
    await replaceConfig(next);
  }
}

class ExpiredBatchOutcome {
  ExpiredBatchOutcome({required this.sent, required this.failed});

  final int sent;
  final int failed;
}
