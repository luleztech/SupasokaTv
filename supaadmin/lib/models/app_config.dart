// ignore_for_file: public_member_api_docs

import 'dart:convert';

/// API / JSON may send [int], [double], or [String] (e.g. Postgres BIGINT).
int? parseIntNullable(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

int parseIntLoose(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.parse(v.toString());
}

/// `malipoPlans.accent1` / `accent2` may be [num] or hex-ish [String] (`0xff…`, `959977`, etc.).
int malipoAccentFromJson(dynamic value, int fallback) {
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

/// Serializable bundle for export / mobile Remote Config later.
class AppConfig {
  AppConfig({
    required this.channels,
    required this.carousel,
    required this.premiumPackages,
    required this.malipoPlans,
    required this.liveMatches,
    required this.notificationLog,
    required this.users,
    this.configVersion = 1,
    this.customerCareWhatsapp = '212600000000',
    this.minAndroidBuild = 0,
    this.minAndroidVersion = '',
    this.latestAndroidVersion = '',
    this.latestAndroidBuild = 0,
    this.forceUpdateEnabled = false,
    this.playStoreUrl = 'https://play.google.com/store/apps/details?id=com.ayubu.supasoka',
  });

  int configVersion;
  List<ChannelDto> channels;
  List<CarouselDto> carousel;
  List<PackageDto> premiumPackages;
  List<MalipoPlanDto> malipoPlans;
  List<LiveMatchDto> liveMatches;
  List<NotificationEntryDto> notificationLog;
  /// Viewer accounts (device id / username) — premium end stored as epoch ms; `null` = free tier.
  List<UserDto> users;
  /// E.164 digits only (no +), used for `wa.me` in the viewer app (FAB + Settings).
  String customerCareWhatsapp;
  /// Minimum Android build number (`versionCode`) required to use the app. `0` = no force update.
  int minAndroidBuild;
  /// Minimum semver label shown to users (e.g. `1.1.8`).
  String minAndroidVersion;
  /// Latest release label shown on the update screen (e.g. `1.2.0`).
  String latestAndroidVersion;
  /// Latest Play Store build number (optional; falls back to [minAndroidBuild]).
  int latestAndroidBuild;
  /// When true, users below [minAndroidBuild] must update before using the app.
  bool forceUpdateEnabled;
  /// Play Store listing URL opened when users tap update.
  String playStoreUrl;

  Map<String, dynamic> toJson() => {
        'configVersion': configVersion,
        'channels': channels.map((e) => e.toJson()).toList(),
        'carousel': carousel.map((e) => e.toJson()).toList(),
        'premiumPackages': premiumPackages.map((e) => e.toJson()).toList(),
        'malipoPlans': malipoPlans.map((e) => e.toJson()).toList(),
        'liveMatches': liveMatches.map((e) => e.toJson()).toList(),
        'notificationLog': notificationLog.map((e) => e.toJson()).toList(),
        'users': users.map((e) => e.toJson()).toList(),
        'customerCareWhatsapp': customerCareWhatsapp,
        'minAndroidBuild': minAndroidBuild,
        'minAndroidVersion': minAndroidVersion,
        'latestAndroidVersion': latestAndroidVersion,
        'latestAndroidBuild': latestAndroidBuild,
        'forceUpdateEnabled': forceUpdateEnabled,
        'playStoreUrl': playStoreUrl,
      };

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    return AppConfig(
      configVersion: (j['configVersion'] as num?)?.toInt() ?? 1,
      channels: (j['channels'] as List<dynamic>? ?? []).map((e) => ChannelDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      carousel: (j['carousel'] as List<dynamic>? ?? []).map((e) => CarouselDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      premiumPackages: (j['premiumPackages'] as List<dynamic>? ?? []).map((e) => PackageDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      malipoPlans: (j['malipoPlans'] as List<dynamic>? ?? []).map((e) => MalipoPlanDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      liveMatches: (j['liveMatches'] as List<dynamic>? ?? []).map((e) => LiveMatchDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      notificationLog: (j['notificationLog'] as List<dynamic>? ?? []).map((e) => NotificationEntryDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      users: (j['users'] as List<dynamic>? ?? []).map((e) => UserDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      customerCareWhatsapp: normalizeCustomerCareWhatsapp(j['customerCareWhatsapp'] as String?),
      minAndroidBuild: (j['minAndroidBuild'] as num?)?.toInt() ?? 0,
      minAndroidVersion: j['minAndroidVersion'] as String? ?? '',
      latestAndroidVersion: j['latestAndroidVersion'] as String? ?? '',
      latestAndroidBuild: (j['latestAndroidBuild'] as num?)?.toInt() ?? 0,
      forceUpdateEnabled: j['forceUpdateEnabled'] as bool? ?? false,
      playStoreUrl: (j['playStoreUrl'] as String?)?.trim().isNotEmpty == true
          ? (j['playStoreUrl'] as String).trim()
          : 'https://play.google.com/store/apps/details?id=com.ayubu.supasoka',
    );
  }

  String toJsonString() => jsonEncode(toJson());

  /// Catalog-only payload for bulk sync — skips notification log (server ignores it).
  Map<String, dynamic> toCatalogSyncJson() {
    final j = toJson();
    j.remove('notificationLog');
    return j;
  }

  static AppConfig fromJsonString(String s) => AppConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

class ChannelDto {
  ChannelDto({
    required this.id,
    required this.name,
    required this.cat,
    required this.img,
    required this.free,
    required this.viewers,
    this.url = '',
    this.enabled = true,
    this.drm = 'none',
    this.clearKeyKidKey = '',
    this.audioLanguage = 'sw',
  });

  int id;
  String name;
  /// Filter key: `mpira` | `movies` | `habari` (legacy keys normalized on load).
  String cat;
  String img;
  /// `true` = free to watch; `false` = premium (subscription required).
  bool free;
  String viewers;
  /// Stream or playback URL.
  String url;
  /// When `false`, channel is hidden/disabled in the app.
  bool enabled;
  /// DRM: `none` | `clearkey` | `widevine`
  String drm;
  /// ClearKey only: `keyId:key` (hex or base64 strings, one colon between KID and key).
  String clearKeyKidKey;
  /// Preferred playback audio: `sw` (Swahili, default) | `en` (English).
  String audioLanguage;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cat': cat,
        'img': img,
        'free': free,
        'viewers': viewers,
        'url': url,
        'enabled': enabled,
        'drm': drm,
        'clearKeyKidKey': clearKeyKidKey,
        'audioLanguage': audioLanguage,
      };

  factory ChannelDto.fromJson(Map<String, dynamic> j) => ChannelDto(
        id: parseIntLoose(j['id']),
        name: j['name'] as String,
        cat: normalizeChannelCategory(j['cat'] as String?),
        img: j['img'] as String,
        free: j['free'] as bool,
        viewers: j['viewers'] as String,
        url: j['url'] as String? ?? '',
        enabled: j['enabled'] as bool? ?? true,
        drm: normalizeChannelDrm(j['drm'] as String?),
        clearKeyKidKey: j['clearKeyKidKey'] as String? ?? '',
        audioLanguage: normalizeChannelAudioLanguage(j['audioLanguage'] as String?),
      );

  ChannelDto copy() => ChannelDto(
        id: id,
        name: name,
        cat: cat,
        img: img,
        free: free,
        viewers: viewers,
        url: url,
        enabled: enabled,
        drm: drm,
        clearKeyKidKey: clearKeyKidKey,
        audioLanguage: audioLanguage,
      );

  ChannelDto copyWith({
    int? id,
    String? name,
    String? cat,
    String? img,
    bool? free,
    String? viewers,
    String? url,
    bool? enabled,
    String? drm,
    String? clearKeyKidKey,
    String? audioLanguage,
  }) {
    return ChannelDto(
      id: id ?? this.id,
      name: name ?? this.name,
      cat: cat ?? this.cat,
      img: img ?? this.img,
      free: free ?? this.free,
      viewers: viewers ?? this.viewers,
      url: url ?? this.url,
      enabled: enabled ?? this.enabled,
      drm: drm ?? this.drm,
      clearKeyKidKey: clearKeyKidKey ?? this.clearKeyKidKey,
      audioLanguage: audioLanguage ?? this.audioLanguage,
    );
  }
}

/// Selectable categories in SupaAdmin (key → label). Mpira, Movies, Habari.
const kChannelCategoryOptions = <String, String>{
  'mpira': 'Mpira',
  'movies': 'Movies',
  'habari': 'Habari',
};

/// DRM options for playback (ClearKey / Widevine).
const kChannelDrmOptions = <String, String>{
  'none': 'None',
  'clearkey': 'ClearKey',
  'widevine': 'Widevine',
};

String channelCategoryLabel(String cat) => kChannelCategoryOptions[cat] ?? cat;

String channelDrmLabel(String drm) => kChannelDrmOptions[drm] ?? drm;

/// Selectable audio languages for channel playback.
const kChannelAudioLanguageOptions = <String, String>{
  'sw': 'Swahili',
  'en': 'English',
};

String channelAudioLanguageLabel(String lang) => kChannelAudioLanguageOptions[lang] ?? lang;

String normalizeChannelAudioLanguage(String? raw) {
  final r = (raw ?? 'sw').toLowerCase().trim();
  if (kChannelAudioLanguageOptions.containsKey(r)) return r;
  if (r.startsWith('en') || r == 'english' || r == 'eng') return 'en';
  if (r.startsWith('sw') || r == 'swahili' || r == 'kiswahili' || r == 'swa') return 'sw';
  return 'sw';
}

String normalizeChannelDrm(String? raw) {
  final r = (raw ?? 'none').toLowerCase().trim();
  if (kChannelDrmOptions.containsKey(r)) return r;
  return 'none';
}

String normalizeChannelCategory(String? raw) {
  final r = (raw ?? 'movies').toLowerCase().trim();
  if (kChannelCategoryOptions.containsKey(r)) return r;
  switch (r) {
    case 'football':
    case 'sports':
    case 'mpira':
      return 'mpira';
    case 'news':
    case 'habari':
      return 'habari';
    case 'movies':
    case 'entertainment':
    case 'tamthilia':
      return 'movies';
    default:
      return 'movies';
  }
}

class CarouselDto {
  CarouselDto({
    required this.badge,
    required this.badgeIcon,
    required this.title,
    required this.channelId,
    required this.img,
  });

  String badge;
  String badgeIcon;
  String title;
  int channelId;
  String img;

  Map<String, dynamic> toJson() => {
        'badge': badge,
        'badgeIcon': badgeIcon,
        'title': title,
        'channelId': channelId,
        'img': img,
      };

  factory CarouselDto.fromJson(Map<String, dynamic> j) => CarouselDto(
        badge: j['badge'] as String,
        badgeIcon: j['badgeIcon'] as String,
        title: j['title'] as String,
        channelId: parseIntLoose(j['channelId']),
        img: j['img'] as String,
      );
}

class PackageDto {
  PackageDto({
    required this.id,
    required this.name,
    required this.price,
    required this.period,
    required this.features,
    required this.popular,
  });

  String id;
  String name;
  String price;
  String period;
  List<String> features;
  bool popular;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'period': period,
        'features': features,
        'popular': popular,
      };

  factory PackageDto.fromJson(Map<String, dynamic> j) => PackageDto(
        id: j['id'] as String,
        name: j['name'] as String,
        price: j['price'] as String,
        period: j['period'] as String,
        features: List<String>.from(j['features'] as List<dynamic>? ?? []),
        popular: j['popular'] as bool? ?? false,
      );
}

class MalipoPlanDto {
  MalipoPlanDto({
    required this.id,
    required this.label,
    required this.priceLines,
    required this.amount,
    required this.period,
    required this.popular,
    required this.accent1,
    required this.accent2,
    this.badge = '',
  });

  String id;
  String label;
  String priceLines;
  String amount;
  String period;
  bool popular;
  int accent1;
  int accent2;
  /// Short label on the price card in the app (e.g. PUNGUZO, BORA). Empty = hidden.
  String badge;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'priceLines': priceLines,
        'amount': amount,
        'period': period,
        'popular': popular,
        'accent1': accent1,
        'accent2': accent2,
        'badge': badge,
      };

  factory MalipoPlanDto.fromJson(Map<String, dynamic> j) => MalipoPlanDto(
        id: j['id'] as String,
        label: j['label'] as String,
        priceLines: j['priceLines'] as String,
        amount: j['amount'] as String,
        period: j['period'] as String,
        popular: j['popular'] as bool? ?? false,
        accent1: malipoAccentFromJson(j['accent1'], 0xFF0ea5e9),
        accent2: malipoAccentFromJson(j['accent2'], 0xFF6366f1),
        badge: j['badge'] as String? ?? '',
      );
}

class LiveMatchDto {
  LiveMatchDto({
    required this.id,
    required this.title,
    required this.channelId,
    this.liveBadge = true,
    this.matchTime,
  });

  int id;
  /// Display name of the match (e.g. team vs team).
  String title;
  /// Stream URL and artwork come from this channel in [AppConfig.channels].
  int channelId;
  /// Show a LIVE badge on the card in the viewer app.
  bool liveBadge;
  /// Optional match time (e.g. "tarehe 00/00/2026 muda 00:00").
  String? matchTime;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'channelId': channelId,
        'liveBadge': liveBadge,
        if (matchTime != null) 'matchTime': matchTime,
      };

  factory LiveMatchDto.fromJson(Map<String, dynamic> j) {
    final cid = j['channelId'];
    final c = cid == null ? 0 : parseIntLoose(cid);
    return LiveMatchDto(
      id: parseIntLoose(j['id']),
      title: j['title'] as String,
      channelId: c,
      liveBadge: j['liveBadge'] as bool? ?? true,
      matchTime: j['matchTime'] as String?,
    );
  }
}

class UserDto {
  UserDto({
    required this.id,
    required this.username,
    this.userNumber,
    this.premiumUntilMs,
    this.note = '',
    this.createdAtMs,
  });

  /// Stable id (e.g. `User-xxxxx` from the viewer app).
  String id;
  String username;
  /// User phone / legacy id from payment.
  String? userNumber;
  /// When premium ends; `null` = free (no subscription end set).
  int? premiumUntilMs;
  String note;
  /// Set when loaded from `GET /api/v1/admin/users` (first registration time).
  int? createdAtMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        if (userNumber != null) 'userNumber': userNumber,
        'premiumUntilMs': premiumUntilMs,
        'note': note,
        if (createdAtMs != null) 'createdAtMs': createdAtMs,
      };

  factory UserDto.fromJson(Map<String, dynamic> j) => UserDto(
        id: '${j['id'] ?? ''}',
        username: '${j['username'] ?? j['profile_username'] ?? ''}',
        userNumber: '${j['userNumber'] ?? j['legacyUserId'] ?? j['legacy_user_id'] ?? ''}'.trim().isEmpty
            ? null
            : '${j['userNumber'] ?? j['legacyUserId'] ?? j['legacy_user_id'] ?? ''}',
        premiumUntilMs: parseIntNullable(j['premiumUntilMs']),
        note: j['note'] as String? ?? '',
        createdAtMs: parseIntNullable(j['createdAtMs']),
      );

  UserDto copyWith({
    String? id,
    String? username,
    String? userNumber,
    bool clearUserNumber = false,
    int? premiumUntilMs,
    bool clearPremiumUntilMs = false,
    String? note,
    int? createdAtMs,
    bool clearCreatedAtMs = false,
  }) {
    return UserDto(
      id: id ?? this.id,
      username: username ?? this.username,
      userNumber: clearUserNumber ? null : (userNumber ?? this.userNumber),
      premiumUntilMs: clearPremiumUntilMs ? null : (premiumUntilMs ?? this.premiumUntilMs),
      note: note ?? this.note,
      createdAtMs: clearCreatedAtMs ? null : (createdAtMs ?? this.createdAtMs),
    );
  }

  static bool isPremiumNow(int? premiumUntilMs) {
    if (premiumUntilMs == null) return false;
    return DateTime.fromMillisecondsSinceEpoch(premiumUntilMs).isAfter(DateTime.now());
  }

  static bool isExpired(int? premiumUntilMs) {
    if (premiumUntilMs == null) return false;
    return !DateTime.fromMillisecondsSinceEpoch(premiumUntilMs).isAfter(DateTime.now());
  }
}

class NotificationEntryDto {
  NotificationEntryDto({
    required this.id,
    required this.title,
    required this.body,
    required this.target,
    required this.createdAt,
    this.scheduledFor,
  });

  String id;
  String title;
  String body;
  /// all | premium | free
  String target;
  String createdAt;
  String? scheduledFor;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'target': target,
        'createdAt': createdAt,
        'scheduledFor': scheduledFor,
      };

  factory NotificationEntryDto.fromJson(Map<String, dynamic> j) => NotificationEntryDto(
        id: '${j['id'] ?? ''}',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        target: j['target'] as String? ?? 'all',
        createdAt: j['createdAt']?.toString() ?? '',
        scheduledFor: j['scheduledFor']?.toString(),
      );
}

/// Strips non-digits; falls back if too short. Use for `wa.me/{digits}`.
String normalizeCustomerCareWhatsapp(String? raw) {
  final d = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.length >= 8 && d.length <= 15) return d;
  return '212600000000';
}
