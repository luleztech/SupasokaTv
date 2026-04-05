// ignore_for_file: public_member_api_docs

import 'dart:convert';

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
      };

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    return AppConfig(
      configVersion: j['configVersion'] as int? ?? 1,
      channels: (j['channels'] as List<dynamic>? ?? []).map((e) => ChannelDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      carousel: (j['carousel'] as List<dynamic>? ?? []).map((e) => CarouselDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      premiumPackages: (j['premiumPackages'] as List<dynamic>? ?? []).map((e) => PackageDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      malipoPlans: (j['malipoPlans'] as List<dynamic>? ?? []).map((e) => MalipoPlanDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      liveMatches: (j['liveMatches'] as List<dynamic>? ?? []).map((e) => LiveMatchDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      notificationLog: (j['notificationLog'] as List<dynamic>? ?? []).map((e) => NotificationEntryDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      users: (j['users'] as List<dynamic>? ?? []).map((e) => UserDto.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      customerCareWhatsapp: normalizeCustomerCareWhatsapp(j['customerCareWhatsapp'] as String?),
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

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
      };

  factory ChannelDto.fromJson(Map<String, dynamic> j) => ChannelDto(
        id: j['id'] as int,
        name: j['name'] as String,
        cat: normalizeChannelCategory(j['cat'] as String?),
        img: j['img'] as String,
        free: j['free'] as bool,
        viewers: j['viewers'] as String,
        url: j['url'] as String? ?? '',
        enabled: j['enabled'] as bool? ?? true,
        drm: normalizeChannelDrm(j['drm'] as String?),
        clearKeyKidKey: j['clearKeyKidKey'] as String? ?? '',
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
        channelId: j['channelId'] as int,
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
        accent1: j['accent1'] as int,
        accent2: j['accent2'] as int,
        badge: j['badge'] as String? ?? '',
      );
}

class LiveMatchDto {
  LiveMatchDto({
    required this.id,
    required this.title,
    required this.channelId,
    this.liveBadge = true,
  });

  int id;
  /// Display name of the match (e.g. team vs team).
  String title;
  /// Stream URL and artwork come from this channel in [AppConfig.channels].
  int channelId;
  /// Show a LIVE badge on the card in the viewer app.
  bool liveBadge;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'channelId': channelId,
        'liveBadge': liveBadge,
      };

  factory LiveMatchDto.fromJson(Map<String, dynamic> j) {
    final cid = j['channelId'];
    final migrated = cid is int;
    return LiveMatchDto(
      id: j['id'] as int,
      title: j['title'] as String,
      channelId: migrated ? cid : 0,
      liveBadge: j['liveBadge'] as bool? ?? true,
    );
  }
}

class UserDto {
  UserDto({
    required this.id,
    required this.username,
    this.premiumUntilMs,
    this.note = '',
  });

  /// Stable id (e.g. device `user_id` from the viewer app).
  String id;
  String username;
  /// When premium ends; `null` = free (no subscription end set).
  int? premiumUntilMs;
  String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'premiumUntilMs': premiumUntilMs,
        'note': note,
      };

  factory UserDto.fromJson(Map<String, dynamic> j) => UserDto(
        id: j['id'] as String,
        username: j['username'] as String,
        premiumUntilMs: j['premiumUntilMs'] as int?,
        note: j['note'] as String? ?? '',
      );

  UserDto copyWith({
    String? id,
    String? username,
    int? premiumUntilMs,
    bool clearPremiumUntilMs = false,
    String? note,
  }) {
    return UserDto(
      id: id ?? this.id,
      username: username ?? this.username,
      premiumUntilMs: clearPremiumUntilMs ? null : (premiumUntilMs ?? this.premiumUntilMs),
      note: note ?? this.note,
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
        id: j['id'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        target: j['target'] as String? ?? 'all',
        createdAt: j['createdAt'] as String,
        scheduledFor: j['scheduledFor'] as String?,
      );
}

/// Strips non-digits; falls back if too short. Use for `wa.me/{digits}`.
String normalizeCustomerCareWhatsapp(String? raw) {
  final d = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.length >= 8 && d.length <= 15) return d;
  return '212600000000';
}
