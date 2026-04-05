import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/data/pay_plan.dart';

const _prefsKey = 'supasoka_public_config_cache_v1';

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

class ContentStore extends ChangeNotifier {
  List<Channel> _channels = [];
  List<CarouselSlide> _carousel = [];
  List<LiveMatch> _liveMatches = [];
  List<PackageItem> _packages = [];
  List<PayPlan> _malipoPlans = [];
  String _customerCareWhatsapp = '';
  bool _ready = false;
  String? _loadError;

  bool get ready => _ready;
  String? get loadError => _loadError;
  List<Channel> get channels => _channels;
  List<CarouselSlide> get carouselSlides => _carousel;
  List<LiveMatch> get liveMatches => _liveMatches;
  List<PackageItem> get premiumPackages => _packages;
  List<PayPlan> get malipoPayPlans => _malipoPlans;

  /// E.164 digits for `wa.me` (from API).
  String get customerCareWhatsapp => _customerCareWhatsapp;

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

  Future<void> bootstrap() async {
    _ready = false;
    _loadError = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final base = apiConfigUrl;

    Future<void> applyCached() async {
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _applyConfig(j);
    }

    if (base.isEmpty) {
      await applyCached();
      if (_channels.isEmpty) {
        _loadError =
            'API base URL is not set. Set kRailwayApiBaseUrl in lib/config/deployment.dart to your Railway '
            'API public HTTPS URL (same host if root directory is backend/, or another hostname if you use two services). '
            'Or: flutter build apk --dart-define=API_BASE_URL=https://…';
      } else {
        _loadError = 'API base URL not set; showing last downloaded config.';
      }
      _ready = true;
      notifyListeners();
      return;
    }

    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/api/v1/public/config');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      final body = res.body.trim();

      if (res.statusCode == 200) {
        if (body.startsWith('<!') || body.startsWith('<html')) {
          _loadError =
              'Got HTML instead of JSON — this base URL is probably a static web server, not the Node API. '
              'Use a separate Railway service for backend/ and set kRailwayApiBaseUrl to that service’s public URL.';
        } else {
          Map<String, dynamic>? j;
          try {
            j = jsonDecode(res.body) as Map<String, dynamic>?;
          } catch (_) {
            j = null;
          }
          if (j != null && j['ok'] == true) {
            _applyConfig(j);
            await prefs.setString(_prefsKey, res.body);
            _loadError = null;
            _ready = true;
            notifyListeners();
            return;
          }
          _loadError = 'Invalid API response (expected JSON with ok: true). Check API base URL.';
        }
      } else if (res.statusCode == 404) {
        _loadError =
            'API not found (404). The backend URL may be wrong or the Railway service is missing. '
            'Deploy backend/ and set kRailwayApiBaseUrl to that service’s public HTTPS URL.';
      } else {
        _loadError = 'Server error (${res.statusCode}).';
      }
    } catch (e) {
      _loadError = 'Could not load config: $e';
    }

    await applyCached();
    if (_channels.isNotEmpty && _loadError != null) {
      _loadError = '${_loadError!} Showing cached data.';
    }
    if (_channels.isEmpty && _loadError == null) {
      _loadError = 'No configuration available.';
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> refresh() => bootstrap();

  void _applyConfig(Map<String, dynamic> j) {
    final chRaw = j['channels'] as List<dynamic>? ?? [];
    _channels = <Channel>[];
    for (final e in chRaw) {
      final m = Map<String, dynamic>.from(e as Map);
      if (m['enabled'] == false) continue;
      final stream = (m['streamUrl'] ?? m['url'] ?? '') as String? ?? '';
      _channels.add(
        Channel(
          id: _asInt(m['id']),
          name: m['name'] as String? ?? '',
          cat: m['cat'] as String? ?? 'movies',
          img: m['img'] as String? ?? '',
          free: m['free'] as bool? ?? true,
          viewers: m['viewers'] as String? ?? '',
          streamUrl: stream,
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
        img: m['img'] as String? ?? '',
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
        img: m['img'] as String? ?? '',
        channelId: _asInt(m['channelId']),
      );
    }).toList();

    final pkgRaw = j['premiumPackages'] as List<dynamic>? ?? [];
    _packages = pkgRaw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final feats = m['features'];
      final list = feats is List ? feats.map((x) => x.toString()).toList() : <String>[];
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
      final a1 = _asInt(m['accent1']);
      final a2 = _asInt(m['accent2']);
      return PayPlan(
        id: m['id'] as String? ?? '',
        label: m['label'] as String? ?? '',
        priceLines: m['priceLines'] as String? ?? '',
        amount: m['amount'] as String? ?? '',
        period: m['period'] as String? ?? '',
        popular: m['popular'] as bool? ?? false,
        accent1: Color(a1 & 0xFFFFFFFF),
        accent2: Color(a2 & 0xFFFFFFFF),
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
  }
}
