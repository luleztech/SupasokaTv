import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/services/app_update_service.dart';
import 'package:supasoka/services/user_identity.dart';

enum PlaybackResolveCode {
  ok,
  updateRequired,
  premiumRequired,
  unavailable,
}

class PlaybackSession {
  const PlaybackSession({
    required this.streamUrl,
    this.drm = 'none',
    this.clearKeyKidKey = '',
    this.licenseUrl = '',
    this.free = true,
  });

  final String streamUrl;
  final String drm;
  final String clearKeyKidKey;
  final String licenseUrl;
  final bool free;
}

String nativeDrmTypeForSession(PlaybackSession session) {
  final drm = session.drm.trim().toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');
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
  final PlaybackSession? session;
  final Map<String, dynamic>? updatePayload;

  factory PlaybackResolveResult.ok(PlaybackSession session) =>
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

/// Server-authoritative stream URL — never trust channel list cache for playback.
/// Results are cached briefly so repeat opens feel instant (stale-while-revalidate).
const _playbackCacheTtl = Duration(seconds: 45);

final Map<int, ({PlaybackSession session, DateTime fetchedAt})> _playbackCache = {};

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
        .timeout(const Duration(seconds: 10));

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
      PlaybackSession(
        streamUrl: streamUrl,
        drm: (j['drm'] ?? 'none').toString(),
        clearKeyKidKey: (j['clearKeyKidKey'] ?? '').toString(),
        licenseUrl: (j['licenseUrl'] ?? '').toString(),
        free: j['free'] as bool? ?? true,
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
      cached.session.free &&
      now.difference(cached.fetchedAt) < _playbackCacheTtl) {
    // Only cache free channels; paid streams always re-check premium on server.
    unawaited(_refreshPlaybackCacheEntry(channelId));
    return PlaybackResolveResult.ok(cached.session);
  }
  final result = await _fetchChannelPlayback(channelId);
  if (result.code == PlaybackResolveCode.ok &&
      result.session != null &&
      result.session!.free) {
    _playbackCache[channelId] = (session: result.session!, fetchedAt: now);
  } else {
    _playbackCache.remove(channelId);
  }
  return result;
}

Future<void> _refreshPlaybackCacheEntry(int channelId) async {
  final result = await _fetchChannelPlayback(channelId);
  if (result.code == PlaybackResolveCode.ok &&
      result.session != null &&
      result.session!.free) {
    _playbackCache[channelId] = (session: result.session!, fetchedAt: DateTime.now());
  } else {
    _playbackCache.remove(channelId);
  }
}
