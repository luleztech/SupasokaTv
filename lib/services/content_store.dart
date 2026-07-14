import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/services/playback_service.dart';
import 'package:supasoka/data/pay_plan.dart';
import 'package:supasoka/services/app_update_service.dart';
import 'package:supasoka/util/image_url.dart';

const _prefsKey = 'supasoka_public_config_cache_v2';

/// Last live update policy from server — never infer force-update from stale config cache alone.
const _prefsKeyUpdatePolicyV1 = 'supasoka_update_policy_v1';

/// Last applied `configVersion:configSyncedAt` from API — compared to `/public/config-meta` for fast updates.
const _prefsKeySyncSig = 'supasoka_public_config_sync_sig_v1';

const _configFetchAttempts = 4;

// User-facing only — never include URLs, hostnames, status codes, or exception text.
const _msgNetwork =
    "We can't update right now. Check your connection, then tap Retry.";
const _msgService = 'The service is busy. Please try again in a moment.';
const _msgEmptyList = 'No channels to show yet. Pull down to refresh.';

const _metaPollHeaders = {
  'Cache-Control': 'no-cache',
  'Pragma': 'no-cache',
  'Accept': 'application/json',
  'User-Agent': 'Supasoka/1.1 (Flutter; viewer meta)',
};

/// Retries transient failures (EaMax-style) before surfacing an error.
Future<http.Response> _getPublicConfig(Uri uri, {Map<String, String>? versionHeaders}) async {
  Object? lastError;
  final headers = {
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Accept': 'application/json',
    'User-Agent': 'Supasoka/1.1 (Flutter; viewer)',
    'Accept-Encoding': 'gzip',
    ...?versionHeaders,
  };
  for (var attempt = 0; attempt < _configFetchAttempts; attempt++) {
    try {
      return await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      lastError = e;
      if (attempt < _configFetchAttempts - 1) {
        await Future<void>.delayed(
          Duration(milliseconds: 350 * (1 << attempt)),
        );
      }
    }
  }
  throw lastError!;
}

/// Maps any thrown client error to a single safe sentence (no URIs or stack traces).
String _friendlyNetworkError(Object e) {
  if (kDebugMode) {
    debugPrint('Supasoka config fetch (internal): $e');
  }
  final s = e.toString().toLowerCase();
  if (s.contains('failed to fetch') ||
      s.contains('clientexception') ||
      s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('connection refused') ||
      s.contains('network is unreachable')) {
    return _msgNetwork;
  }
  if (s.contains('handshakeexception') ||
      s.contains('certificate_verify_failed')) {
    return _msgNetwork;
  }
  if (s.contains('timeoutexception')) {
    return _msgService;
  }
  return _msgNetwork;
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

/// Same rules as admin `malipoAccentFromJson`: num or hex-ish string from API/DB.
int _malipoAccentRawFromJson(dynamic value, int fallback) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final s = value.toString().trim();
  if (s.isEmpty) return fallback;
  final lower = s.toLowerCase();
  if (lower.startsWith('0x')) {
    return int.tryParse(lower.substring(2), radix: 16) ?? fallback;
  }
  final hexOnly = RegExp(r'^[0-9a-fA-F]+$').hasMatch(s);
  final len = s.length;
  if (hexOnly && (len == 6 || len == 8)) {
    return int.tryParse(s, radix: 16) ?? fallback;
  }
  return int.tryParse(s, radix: 10) ?? fallback;
}

/// Malipo accents may be 24-bit RGB only (DB INTEGER) or full ARGB (BIGINT).
Color _malipoAccentFromApi(int raw) {
  final u = raw & 0xFFFFFFFF;
  if (u <= 0xFFFFFF) return Color(0xFF000000 | u);
  return Color(u);
}

class ContentStore extends ChangeNotifier {
  List<Channel> _channels = [];
  List<CarouselSlide> _carousel = [];
  List<LiveMatch> _liveMatches = [];
  List<PackageItem> _packages = [];
  List<PayPlan> _malipoPlans = [];
  String _customerCareWhatsapp = '';
  AppUpdateStatus _updateStatus = AppUpdateStatus.upToDate(
    currentVersion: '',
    currentBuild: 0,
    playStoreUrl: kDefaultPlayStoreUrl,
  );
  bool _ready = false;
  bool _refreshing = false;
  bool _connectionBlocked = false;
  String? _loadError;

  bool get ready => _ready;

  /// True when the last config fetch failed with a network reachability error —
  /// catalog is cleared and the app shows the offline gate until [refresh] succeeds.
  bool get connectionBlocked => _connectionBlocked;

  /// True while a silent background fetch ([refresh]) is in progress.
  bool get refreshing => _refreshing;
  String? get loadError => _loadError;
  List<Channel> get channels => _channels;
  List<CarouselSlide> get carouselSlides => _carousel;
  List<LiveMatch> get liveMatches => _liveMatches;
  List<PackageItem> get premiumPackages => _packages;
  List<PayPlan> get malipoPayPlans => _malipoPlans;

  /// E.164 digits for `wa.me` (from API).
  String get customerCareWhatsapp => _customerCareWhatsapp;

  bool get updateRequired => _updateStatus.required;
  AppUpdateStatus get appUpdateStatus => _updateStatus;

  bool get hasValidCustomerCare {
    final d = _customerCareWhatsapp.replaceAll(RegExp(r'\D'), '');
    return d.length >= 8 && d.length <= 15;
  }

  Channel? channelById(int id) {
    for (final c in _channels) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<Uri> _publicUri(String originPath, {Map<String, String>? extra}) async {
    final versionParams = await appVersionQueryParams();
    return Uri.parse(originPath).replace(
      queryParameters: {
        ...versionParams,
        ...?extra,
      },
    );
  }

  Future<Map<String, String>> _versionHeaders() async {
    final params = await appVersionQueryParams();
    return {
      'X-App-Build': params['appBuild'] ?? '',
      'X-App-Version': params['appVersion'] ?? '',
      'X-Supasoka-Build': params['appBuild'] ?? '',
      'X-Supasoka-Version': params['appVersion'] ?? '',
    };
  }

  Future<void> _persistUpdatePolicy(Map<String, dynamic> j) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyUpdatePolicyV1, jsonEncode(j));
  }

  Future<Map<String, dynamic>?> _loadPersistedUpdatePolicy() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyUpdatePolicyV1);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await prefs.remove(_prefsKeyUpdatePolicyV1);
      return null;
    }
  }

  /// Apply update gate from playback/payment API (426) without loading catalog.
  Future<void> applyServerUpdatePayload(Map<String, dynamic>? j) async {
    if (j == null || j.isEmpty) {
      await checkUpdateFromServer();
      return;
    }
    await _persistUpdatePolicy(j);
    await _syncUpdatePolicy(j);
  }

  /// Always hits the server first so older builds pick up new force-update rules.
  Future<bool> checkUpdateFromServer() async {
    final fetched = await _fetchUpdatePolicyFromServer();
    if (fetched) return _updateStatus.required;
    final cached = await _loadPersistedUpdatePolicy();
    if (cached != null) {
      await _syncUpdatePolicy(cached);
    }
    return _updateStatus.required;
  }

  Future<bool> _fetchUpdatePolicyFromServer() async {
    final base = apiConfigUrl.trim();
    if (base.isEmpty) return false;

    final origin = base.replaceAll(RegExp(r'/$'), '');
    final versionHeaders = await _versionHeaders();
    final endpoints = [
      '$origin/api/v1/public/app-update',
      '$origin/api/v1/public/config-meta',
    ];

    for (final path in endpoints) {
      try {
        final uri = await _publicUri(path, extra: {'_': DateTime.now().millisecondsSinceEpoch.toString()});
        final res = await http
            .get(uri, headers: {..._metaPollHeaders, ...versionHeaders})
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;

        Map<String, dynamic>? j;
        try {
          j = jsonDecode(res.body) as Map<String, dynamic>?;
        } catch (_) {
          j = null;
        }
        if (j == null || j['ok'] != true) continue;

        await _persistUpdatePolicy(j);
        await _syncUpdatePolicy(j);
        return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  Future<bool> _applyCachedFromPrefs(SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return false;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _applyConfig(j);
      await _persistSyncSignature(j);
      return true;
    } catch (_) {
      await prefs.remove(_prefsKey);
      return false;
    }
  }

  /// Cold start: hydrate from disk immediately, then refresh from network without blocking navigation.
  Future<void> bootstrapForSplash() async {
    _loadError = null;
    final prefs = await SharedPreferences.getInstance();
    final hadCache = await _applyCachedFromPrefs(prefs);
    if (hadCache && _channels.isNotEmpty) {
      _ready = true;
      notifyListeners();
      unawaited(bootstrap(silent: true));
      return;
    }
    _ready = false;
    _refreshing = true;
    notifyListeners();
    unawaited(bootstrap(silent: false));
  }

  /// [silent]: keep current UI visible while fetching (used for pull-to-refresh and tab changes).
  Future<void> bootstrap({bool silent = false}) async {
    if (!silent) {
      if (_channels.isEmpty) {
        _ready = false;
        _refreshing = true;
      }
      _loadError = null;
    } else {
      _refreshing = true;
    }
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      if (_channels.isEmpty) {
        await _applyCachedFromPrefs(prefs);
        if (_channels.isNotEmpty && !silent) {
          _ready = true;
          notifyListeners();
        }
      }

      final base = apiConfigUrl;

      // Live server policy always wins — do not rely on stale config cache for update gate.
      final livePolicy = await _fetchUpdatePolicyFromServer();
      if (!livePolicy) {
        final cachedPolicy = await _loadPersistedUpdatePolicy();
        if (cachedPolicy != null) {
          await _syncUpdatePolicy(cachedPolicy);
        }
      }
      if (_updateStatus.required) {
        _clearCatalog();
        _connectionBlocked = false;
        _loadError = null;
        _ready = true;
        notifyListeners();
        return;
      }

      Future<void> applyCached() async {
        await _applyCachedFromPrefs(prefs);
      }

      if (base.isEmpty) {
        await applyCached();
        _connectionBlocked = false;
        _loadError = _channels.isEmpty ? _msgNetwork : null;
        _ready = true;
        notifyListeners();
        return;
      }

      final origin = base.replaceAll(RegExp(r'/$'), '');
      final versionHeaders = await _versionHeaders();
      final uri = await _publicUri(
        '$origin/api/v1/public/config',
        extra: {
          '_': DateTime.now().millisecondsSinceEpoch.toString(),
          'r': DateTime.now().microsecondsSinceEpoch.toString(),
        },
      );
      try {
        final res = await _getPublicConfig(uri, versionHeaders: versionHeaders);
        final body = res.body.trim();

        if (res.statusCode == 200) {
          if (body.startsWith('<!') || body.startsWith('<html')) {
            if (kDebugMode) {
              debugPrint(
                'Supasoka: config endpoint returned HTML (wrong host or proxy).',
              );
            }
            _loadError = _msgService;
          } else {
            Map<String, dynamic>? j;
            try {
              j = jsonDecode(res.body) as Map<String, dynamic>?;
            } catch (_) {
              j = null;
            }
            if (j != null && j['ok'] == true) {
              await _persistUpdatePolicy(j);
              await _syncUpdatePolicy(j);
              if (_updateStatus.required) {
                _clearCatalog();
                _connectionBlocked = false;
                _loadError = null;
                _ready = true;
                notifyListeners();
                return;
              }
              _applyConfig(j);
              final channelCount = _channels.length;
              if (channelCount > 0) {
                await prefs.setString(_prefsKey, res.body);
              } else if (kDebugMode) {
                debugPrint(
                  'Supasoka: config ok but 0 channels (check appBuild/appVersion query params).',
                );
              }
              await _persistSyncSignature(j);
              _connectionBlocked = false;
              _loadError = null;
              _ready = true;
              notifyListeners();
              return;
            }
            if (kDebugMode) {
              debugPrint('Supasoka: config JSON missing ok: true.');
            }
            _loadError = _msgService;
          }
        } else {
          if (kDebugMode) {
            debugPrint('Supasoka: config HTTP ${res.statusCode}');
          }
          _loadError = _msgService;
        }
      } catch (e) {
        _loadError = _friendlyNetworkError(e);
      }

      if (_loadError == _msgNetwork) {
        _connectionBlocked = true;
        _clearCatalog();
        _loadError = null;
      } else {
        _connectionBlocked = false;
        await applyCached();
        if (_channels.isEmpty && _loadError == null) {
          _loadError = _msgEmptyList;
        }
      }
      _ready = true;
      notifyListeners();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await checkUpdateFromServer();
    if (_updateStatus.required) {
      _clearCatalog();
      _ready = true;
      notifyListeners();
      return;
    }
    await bootstrap(silent: true);
  }

  /// Lightweight poll (called ~every 3s from [MainShell]). Full config fetch only when admin synced new data.
  Future<void> pollConfigMeta() async {
    if (!_ready || _refreshing) return;
    final base = apiConfigUrl.trim();
    if (base.isEmpty) return;

    final fetched = await _fetchUpdatePolicyFromServer();
    if (!fetched) {
      final cachedPolicy = await _loadPersistedUpdatePolicy();
      if (cachedPolicy != null) {
        await _syncUpdatePolicy(cachedPolicy);
      }
    }
    if (_updateStatus.required) {
      _clearCatalog();
      notifyListeners();
      return;
    }

    final origin = base.replaceAll(RegExp(r'/$'), '');
    final versionHeaders = await _versionHeaders();
    final uri = await _publicUri(
      '$origin/api/v1/public/config-meta',
      extra: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
    );

    try {
      final res = await http
          .get(uri, headers: {..._metaPollHeaders, ...versionHeaders})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return;

      Map<String, dynamic>? j;
      try {
        j = jsonDecode(res.body) as Map<String, dynamic>?;
      } catch (_) {
        j = null;
      }
      if (j == null || j['ok'] != true) return;

      await _persistUpdatePolicy(j);
      await _syncUpdatePolicy(j);
      if (_updateStatus.required) {
        _clearCatalog();
        notifyListeners();
        return;
      }

      final remoteSig = _syncSignatureFromJson(j);
      final prefs = await SharedPreferences.getInstance();
      final localSig = prefs.getString(_prefsKeySyncSig);
      if (localSig != null && localSig == remoteSig) return;

      await refresh();
    } catch (_) {
      // Offline or meta route missing on old API — ignore; full refresh happens on resume / pull-to-refresh.
    }
  }

  String _syncSignatureFromJson(Map<String, dynamic> j) {
    final cv = _asInt(j['configVersion']);
    final cs = j['configSyncedAt'];
    var syncedMs = 0;
    if (cs is num) {
      syncedMs = cs.toInt();
    } else if (cs != null) {
      syncedMs = int.tryParse(cs.toString()) ?? 0;
    }
    return '$cv:$syncedMs';
  }

  Future<void> _persistSyncSignature(Map<String, dynamic> j) async {
    final sig = _syncSignatureFromJson(j);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeySyncSig, sig);
  }

  void _clearCatalog() {
    _channels = [];
    _carousel = [];
    _liveMatches = [];
    _packages = [];
    _malipoPlans = [];
    _customerCareWhatsapp = '';
  }

  void _applyConfig(Map<String, dynamic> j) {
    final chRaw = j['channels'] as List<dynamic>? ?? [];
    _channels = <Channel>[];
    for (final e in chRaw) {
      final m = Map<String, dynamic>.from(e as Map);
      if (m['enabled'] == false) continue;
      _channels.add(
        Channel(
          id: _asInt(m['id']),
          name: m['name'] as String? ?? '',
          cat: m['cat'] as String? ?? 'movies',
          img: sanitizeImageUrl(m['img'] as String? ?? ''),
          free: m['free'] as bool? ?? true,
          viewers: m['viewers'] as String? ?? '',
          streamUrl: (m['streamUrl'] as String? ?? m['url'] as String? ?? '').trim(),
          drm: (m['drm'] as String? ?? 'none').trim(),
          clearKeyKidKey: '',
          licenseUrl: '',
          audioLanguage: normalizePlaybackAudioLanguage(m['audioLanguage'] as String?),
        ),
      );
    }

    final carRaw = j['carousel'] as List<dynamic>? ?? [];
    _carousel = carRaw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return CarouselSlide(
        badge: m['badge'] as String? ?? '',
        badgeIcon: m['badgeIcon'] as String? ?? '',
        title: m['title'] as String? ?? '',
        channelId: _asInt(m['channelId']),
        img: sanitizeImageUrl(m['img'] as String? ?? ''),
      );
    }).toList();

    final liveRaw = j['liveMatches'] as List<dynamic>? ?? [];
    _liveMatches = liveRaw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return LiveMatch(
        id: _asInt(m['id']),
        title: m['title'] as String? ?? '',
        sport: m['sport'] as String? ?? '',
        sportIcon: m['sportIcon'] as String? ?? '',
        img: sanitizeImageUrl(m['img'] as String? ?? ''),
        channelId: _asInt(m['channelId']),
        matchTime: m['matchTime'] as String?,
      );
    }).toList();

    final pkgRaw = j['premiumPackages'] as List<dynamic>? ?? [];
    _packages = pkgRaw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final feats = m['features'];
      final list = feats is List
          ? feats.map((x) => x.toString()).toList()
          : <String>[];
      return PackageItem(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        price: m['price'] as String? ?? '',
        period: m['period'] as String? ?? '',
        features: list,
        popular: m['popular'] as bool? ?? false,
      );
    }).toList();

    final malRaw = j['malipoPlans'] as List<dynamic>? ?? [];
    _malipoPlans = malRaw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final a1 = _malipoAccentRawFromJson(m['accent1'], 0xFF0ea5e9);
      final a2 = _malipoAccentRawFromJson(m['accent2'], 0xFF6366f1);
      return PayPlan(
        id: m['id'] as String? ?? '',
        label: m['label'] as String? ?? '',
        priceLines: m['priceLines'] as String? ?? '',
        amount: m['amount'] as String? ?? '',
        period: m['period'] as String? ?? '',
        popular: m['popular'] as bool? ?? false,
        accent1: _malipoAccentFromApi(a1),
        accent2: _malipoAccentFromApi(a2),
        badge: m['badge'] as String? ?? '',
      );
    }).toList();

    var wa = j['customerCareWhatsapp'] as String? ?? '';
    wa = wa.replaceAll(RegExp(r'\D'), '');
    if (wa.length >= 8 && wa.length <= 15) {
      _customerCareWhatsapp = wa;
    } else {
      _customerCareWhatsapp = '';
    }

    unawaited(warmPlaybackCache(_channels.map((c) => c.id)));
  }

  Future<void> _syncUpdatePolicy(Map<String, dynamic> j) async {
    _updateStatus = await evaluateAppUpdateFromConfig(j);
    if (_updateStatus.required) {
      _clearCatalog();
    }
    notifyListeners();
  }
}
