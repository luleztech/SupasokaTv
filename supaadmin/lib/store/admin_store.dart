import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config.dart';

const _prefsKey = 'supaadmin_app_config_v1';

AppConfig _defaultConfig() {
  return AppConfig(
    configVersion: 1,
    channels: [
      ChannelDto(id: 0, name: 'Vero Sports HD', cat: 'mpira', img: 'https://picsum.photos/seed/bein1/400/220', free: true, viewers: '24.1K', url: '', enabled: true, drm: 'none'),
      ChannelDto(id: 1, name: 'Aero Sports Premier', cat: 'mpira', img: 'https://picsum.photos/seed/sky2/400/220', free: false, viewers: '18.9K', url: '', enabled: true, drm: 'widevine'),
      ChannelDto(id: 2, name: 'Flixora Originals', cat: 'movies', img: 'https://picsum.photos/seed/netf3/400/220', free: true, viewers: '32K', url: '', enabled: true, drm: 'none'),
      ChannelDto(id: 3, name: 'Cinemax Ultra', cat: 'movies', img: 'https://picsum.photos/seed/hbo4/400/220', free: false, viewers: '11.3K', url: '', enabled: true, drm: 'clearkey'),
      ChannelDto(id: 4, name: 'SportVex HD', cat: 'mpira', img: 'https://picsum.photos/seed/espn5/400/220', free: true, viewers: '9.7K', url: '', enabled: true, drm: 'none'),
      ChannelDto(id: 5, name: 'Nexosport HD', cat: 'habari', img: 'https://picsum.photos/seed/euro6/400/220', free: false, viewers: '7.2K', url: '', enabled: true, drm: 'widevine'),
      ChannelDto(id: 6, name: 'Vibra Entertainment', cat: 'movies', img: 'https://picsum.photos/seed/mtv7/400/220', free: true, viewers: '15K', url: '', enabled: true, drm: 'none'),
      ChannelDto(id: 7, name: 'Explorix Channel', cat: 'movies', img: 'https://picsum.photos/seed/disc8/400/220', free: false, viewers: '6.4K', url: '', enabled: true, drm: 'clearkey'),
      ChannelDto(id: 8, name: 'Globex World News', cat: 'habari', img: 'https://picsum.photos/seed/bbc9/400/220', free: true, viewers: '21K', url: '', enabled: true, drm: 'none'),
      ChannelDto(id: 9, name: 'Arivo News Live', cat: 'habari', img: 'https://picsum.photos/seed/alj10/400/220', free: false, viewers: '13.5K', url: '', enabled: true, drm: 'none'),
      ChannelDto(id: 10, name: 'Lorium Liga TV', cat: 'mpira', img: 'https://picsum.photos/seed/laliga11/400/220', free: false, viewers: '8.8K', url: '', enabled: true, drm: 'widevine'),
      ChannelDto(id: 11, name: 'Cinevox Movies 4K', cat: 'movies', img: 'https://picsum.photos/seed/action12/400/220', free: true, viewers: '19K', url: '', enabled: true, drm: 'none'),
    ],
    carousel: [
      CarouselDto(badge: 'LIVE NOW', badgeIcon: 'radio-outline', title: 'Lorem Cup\nFinal 2025', channelId: 0, img: 'https://picsum.photos/seed/match1/800/400'),
      CarouselDto(badge: 'NEW MOVIE', badgeIcon: 'film-outline', title: 'The Lorem\nIpsum', channelId: 2, img: 'https://picsum.photos/seed/movie22/800/400'),
      CarouselDto(badge: 'TONIGHT', badgeIcon: 'trophy-outline', title: 'Lorem League\nDerby Night', channelId: 1, img: 'https://picsum.photos/seed/sport5/800/400'),
      CarouselDto(badge: 'ENTERTAINMENT', badgeIcon: 'musical-notes-outline', title: 'Dolor Night\nLive Stream', channelId: 3, img: 'https://picsum.photos/seed/enter9/800/400'),
    ],
    premiumPackages: [
      PackageDto(id: 'daily', name: 'Daily Pass', price: r'$1.99', period: '/day', features: ['All Channels', 'HD Quality', '1 Device'], popular: false),
      PackageDto(id: 'weekly', name: 'Weekly Pack', price: r'$7.99', period: '/week', features: ['All Channels', 'Full HD', '2 Devices', 'Catch-up TV'], popular: true),
      PackageDto(id: 'monthly', name: 'Monthly Pro', price: r'$19.99', period: '/month', features: ['All Channels', '4K Ultra', '4 Devices', 'Catch-up TV', 'Download'], popular: false),
    ],
    malipoPlans: [
      MalipoPlanDto(id: 'weekly', label: 'Wiki 1', priceLines: 'TSh\n2,000', amount: 'TSh 2,000', period: 'Wiki Moja', popular: false, accent1: 0xFF0ea5e9, accent2: 0xFF6366f1, badge: 'MPYA'),
      MalipoPlanDto(id: 'monthly', label: 'Mwezi', priceLines: 'TSh\n5,000', amount: 'TSh 5,000', period: 'Mwezi Moja', popular: true, accent1: 0xFFa855f7, accent2: 0xFFec4899, badge: 'BORA'),
      MalipoPlanDto(id: 'yearly', label: 'Mwaka', priceLines: 'TSh\n12,000', amount: 'TSh 12,000', period: 'Mwaka Mzima', popular: false, accent1: 0xFFf59e0b, accent2: 0xFFef4444, badge: 'PUNGUZO'),
    ],
    liveMatches: [
      LiveMatchDto(id: 0, title: 'Lorem FC vs Ipsum United', channelId: 0, liveBadge: true),
      LiveMatchDto(id: 1, title: 'Dolor City vs Amet FC', channelId: 1, liveBadge: true),
      LiveMatchDto(id: 2, title: 'Lorem Hawks vs Ipsum Bulls', channelId: 4, liveBadge: false),
      LiveMatchDto(id: 3, title: 'Lorem Open Final', channelId: 2, liveBadge: true),
      LiveMatchDto(id: 4, title: 'Lorem Grand Prix Series', channelId: 5, liveBadge: false),
      LiveMatchDto(id: 5, title: 'Lorem Championship Fight', channelId: 3, liveBadge: true),
    ],
    notificationLog: [],
    users: [
      UserDto(
        id: 'usr_demo1',
        username: 'k7mpo2a9',
        premiumUntilMs: DateTime.now().add(const Duration(days: 25)).millisecondsSinceEpoch,
        note: 'Premium active',
      ),
      UserDto(
        id: 'usr_demo2',
        username: 'expired_x3',
        premiumUntilMs: DateTime.now().subtract(const Duration(days: 5)).millisecondsSinceEpoch,
        note: 'Expired',
      ),
      UserDto(
        id: 'usr_demo3',
        username: 'free_only',
        premiumUntilMs: null,
        note: 'Free tier',
      ),
    ],
  );
}

class AdminStore extends ChangeNotifier {
  AdminStore() {
    _config = _defaultConfig();
  }

  late AppConfig _config;
  bool _loaded = false;
  bool get isLoaded => _loaded;

  AppConfig get config => _config;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _config = AppConfig.fromJsonString(raw);
      } catch (_) {
        _config = _defaultConfig();
      }
    } else {
      _config = _defaultConfig();
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, _config.toJsonString());
    notifyListeners();
  }

  Future<void> replaceConfig(AppConfig next) async {
    _config = next;
    await _persist();
  }

  Future<void> resetToDefaults() async {
    _config = _defaultConfig();
    await _persist();
  }

  Future<void> setCustomerCareWhatsapp(String raw) async {
    _config.customerCareWhatsapp = normalizeCustomerCareWhatsapp(raw);
    await _persist();
  }

  // —— Channels ——
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

  // —— Carousel ——
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

  // —— Premium packages ——
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

  // —— Malipo ——
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

  // —— Live matches ——
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

  // —— Notifications ——
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

  // —— Users (subscriptions) ——
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
    _config.users.removeWhere((u) => u.id == id);
    await _persist();
  }

  /// Adds [duration] to the user’s current end (or from now if none / expired), like the viewer app.
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
