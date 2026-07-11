import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/services/app_update_service.dart';
import 'package:supasoka/services/user_identity.dart';

enum PlaybackResolveCode {
  ok,
  updateRequired,
  premiumRequired,
  unavailable,
}

class ApiPlaybackSession {
  const ApiPlaybackSession({
    required this.streamUrl,
    this.drm = 'none',
    this.clearKeyKidKey = '',
    this.licenseUrl = '',
    this.free = true,
    this.audioLanguage = 'sw',
    this.playbackHeaders = const {},
  });

  final String streamUrl;
  final String drm;
  final String clearKeyKidKey;
  final String licenseUrl;
  final bool free;
  /// Preferred audio track: `sw` (Swahili) | `en` (English).
  final String audioLanguage;
  final Map<String, String> playbackHeaders;
}

String normalizePlaybackAudioLanguage(String? raw) {
  final r = (raw ?? 'sw').toLowerCase().trim();
  if (r == 'en' || r.startsWith('en-') || r == 'english' || r == 'eng') return 'en';
  if (r == 'sw' || r.startsWith('sw-') || r == 'swahili' || r == 'kiswahili' || r == 'swa') return 'sw';
  return 'sw';
}

/// Play-time audio preference: playback API wins when `en`; else channel config (admin).
String resolvePlaybackAudioLanguage({
  required ApiPlaybackSession session,
  Channel? channel,
}) {
  final api = normalizePlaybackAudioLanguage(session.audioLanguage);
  final cfg = normalizePlaybackAudioLanguage(channel?.audioLanguage);
  if (api == 'en' || cfg == 'en') return 'en';
  return 'sw';
}

ApiPlaybackSession sessionWithResolvedAudioLanguage(
  ApiPlaybackSession session,
  Channel? channel,
) {
  return ApiPlaybackSession(
    streamUrl: session.streamUrl,
    drm: session.drm,
    clearKeyKidKey: session.clearKeyKidKey,
    licenseUrl: session.licenseUrl,
    free: session.free,
    audioLanguage: resolvePlaybackAudioLanguage(session: session, channel: channel),
    playbackHeaders: session.playbackHeaders,
  );
}

String _normalizedDrmLabel(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');

/// Public channel list omits DRM secrets — those channels need `/playback` first.
bool channelRequiresPlaybackResolve(Channel channel) {
  final drm = _normalizedDrmLabel(channel.drm);
  return drm != 'none' && drm.isNotEmpty;
}

/// True when a session advertises DRM but is missing keys/license from the API.
bool playbackSessionMissingSecrets(ApiPlaybackSession session) {
  final drm = _normalizedDrmLabel(session.drm);
  switch (drm) {
    case 'none':
    case '':
      return false;
    case 'clearkey':
      return session.clearKeyKidKey.trim().isEmpty;
    case 'widevine':
    case 'widevinel1':
    case 'widevinel3':
    case 'playready':
      return session.licenseUrl.trim().isEmpty;
    default:
      return true;
  }
}

String nativeDrmTypeForSession(ApiPlaybackSession session) {
  final drm = _normalizedDrmLabel(session.drm);
  switch (drm) {
    case 'clearkey':
      return session.clearKeyKidKey.trim().isEmpty ? 'NONE' : 'CLEARKEY';
    case 'widevine':
      return 'WIDEVINE';
    case 'widevinel1':
      return 'WIDEVINE_L1';
    case 'widevinel3':
      return 'WIDEVINE_L3';
    case 'playready':
      return 'PLAYREADY';
    default:
      return 'NONE';
  }
}

class PlaybackResolveResult {
  const PlaybackResolveResult._({
    required this.code,
    this.session,
    this.updatePayload,
  });

  final PlaybackResolveCode code;
  final ApiPlaybackSession? session;
  final Map<String, dynamic>? updatePayload;

  factory PlaybackResolveResult.ok(ApiPlaybackSession session) =>
      PlaybackResolveResult._(code: PlaybackResolveCode.ok, session: session);

  factory PlaybackResolveResult.updateRequired(Map<String, dynamic>? payload) =>
      PlaybackResolveResult._(
        code: PlaybackResolveCode.updateRequired,
        updatePayload: payload,
      );

  factory PlaybackResolveResult.premiumRequired() =>
      const PlaybackResolveResult._(code: PlaybackResolveCode.premiumRequired);

  factory PlaybackResolveResult.unavailable() =>
      const PlaybackResolveResult._(code: PlaybackResolveCode.unavailable);
}

Future<Map<String, String>> _versionHeaders() async {
  final params = await appVersionQueryParams();
  return {
    'Cache-Control': 'no-cache',
    'Accept': 'application/json',
    'X-App-Build': params['appBuild'] ?? '',
    'X-App-Version': params['appVersion'] ?? '',
    'X-Supasoka-Build': params['appBuild'] ?? '',
    'X-Supasoka-Version': params['appVersion'] ?? '',
  };
}

/// Server-authoritative stream URL — list cache enables one-tap play; API refreshes DRM/premium.
/// Results are cached so repeat opens feel instant (stale-while-revalidate).
const _playbackCacheTtl = Duration(minutes: 5);

final Map<int, ({ApiPlaybackSession session, DateTime fetchedAt})> _playbackCache = {};

/// Instant read — no await. Used for one-tap channel open.
ApiPlaybackSession? peekCachedPlayback(int channelId) {
  final cached = _playbackCache[channelId];
  if (cached == null) return null;
  if (DateTime.now().difference(cached.fetchedAt) >= _playbackCacheTtl) return null;
  return cached.session;
}

Map<String, String> _playbackHeadersFromJson(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, String>{};
  raw.forEach((key, value) {
    final k = key.toString().trim();
    final v = value?.toString().trim() ?? '';
    if (k.isNotEmpty && v.isNotEmpty) out[k] = v;
  });
  return out;
}

ApiPlaybackSession apiSessionFromChannel(Channel channel) {
  return ApiPlaybackSession(
    streamUrl: channel.streamUrl.trim(),
    drm: channel.drm,
    clearKeyKidKey: channel.clearKeyKidKey.trim(),
    licenseUrl: channel.licenseUrl.trim(),
    free: channel.free,
    audioLanguage: normalizePlaybackAudioLanguage(channel.audioLanguage),
  );
}

void invalidatePlaybackCache([int? channelId]) {
  if (channelId == null) {
    _playbackCache.clear();
  } else {
    _playbackCache.remove(channelId);
  }
}

Future<PlaybackResolveResult> _fetchChannelPlayback(int channelId) async {
  final base = apiConfigUrl.trim();
  if (base.isEmpty) return PlaybackResolveResult.unavailable();

  final userId = await UserIdentity.getOrCreatePublicId();
  final origin = base.replaceAll(RegExp(r'/$'), '');
  final versionParams = await appVersionQueryParams();
  final uri = Uri.parse('$origin/api/v1/public/playback/$channelId').replace(
    queryParameters: {
      'userId': userId,
      ...versionParams,
      '_': DateTime.now().millisecondsSinceEpoch.toString(),
    },
  );

  try {
    final res = await http
        .get(uri, headers: await _versionHeaders())
        .timeout(const Duration(seconds: 6));

    Map<String, dynamic>? j;
    try {
      j = jsonDecode(res.body) as Map<String, dynamic>?;
    } catch (_) {
      j = null;
    }

    if (res.statusCode == 426 || j?['updateRequired'] == true) {
      return PlaybackResolveResult.updateRequired(j);
    }
    if (res.statusCode == 403 && j?['premiumRequired'] == true) {
      _playbackCache.remove(channelId);
      return PlaybackResolveResult.premiumRequired();
    }
    if (res.statusCode != 200 || j == null || j['ok'] != true) {
      return PlaybackResolveResult.unavailable();
    }

    final streamUrl = (j['streamUrl'] as String?)?.trim() ?? '';
    if (streamUrl.isEmpty) return PlaybackResolveResult.unavailable();

    return PlaybackResolveResult.ok(
      ApiPlaybackSession(
        streamUrl: streamUrl,
        drm: (j['drm'] ?? 'none').toString(),
        clearKeyKidKey: (j['clearKeyKidKey'] ?? '').toString(),
        licenseUrl: (j['licenseUrl'] ?? '').toString(),
        free: j['free'] as bool? ?? true,
        audioLanguage: normalizePlaybackAudioLanguage(j['audioLanguage']?.toString()),
        playbackHeaders: _playbackHeadersFromJson(j['playbackHeaders']),
      ),
    );
  } catch (_) {
    return PlaybackResolveResult.unavailable();
  }
}

Future<PlaybackResolveResult> resolveChannelPlayback(
  int channelId, {
  bool bypassCache = false,
}) async {
  final cached = _playbackCache[channelId];
  final now = DateTime.now();
  if (!bypassCache &&
      cached != null &&
      now.difference(cached.fetchedAt) < _playbackCacheTtl) {
    unawaited(_refreshPlaybackCacheEntry(channelId));
    return PlaybackResolveResult.ok(cached.session);
  }
  final result = await _fetchChannelPlayback(channelId);
  if (result.code == PlaybackResolveCode.ok && result.session != null) {
    _playbackCache[channelId] = (session: result.session!, fetchedAt: now);
  } else {
    _playbackCache.remove(channelId);
  }
  return result;
}

/// Prefetch playback sessions in the background so the first tap is instant.
Future<void> warmPlaybackCache(
  Iterable<int> channelIds, {
  int concurrency = 8,
}) async {
  final pending = channelIds.where((id) => id > 0).toList();
  if (pending.isEmpty) return;
  var index = 0;
  Future<void> worker() async {
    while (index < pending.length) {
      final id = pending[index++];
      if (peekCachedPlayback(id) != null) continue;
      try {
        await resolveChannelPlayback(id);
      } catch (_) {}
    }
  }
  final workers = List<Future<void>>.generate(
    concurrency.clamp(1, pending.length),
    (_) => worker(),
  );
  await Future.wait(workers);
}

Future<void> _refreshPlaybackCacheEntry(int channelId) async {
  final result = await _fetchChannelPlayback(channelId);
  if (result.code == PlaybackResolveCode.ok && result.session != null) {
    _playbackCache[channelId] = (session: result.session!, fetchedAt: DateTime.now());
  } else {
    _playbackCache.remove(channelId);
  }
}
