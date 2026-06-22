import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/player/playback_helpers.dart';
import 'package:supasoka/player/playback_http_headers.dart';
import 'package:supasoka/screens/payment_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/playback_service.dart';
import 'package:supasoka/services/player_playback_service.dart';
import 'package:supasoka/services/premium_recovery.dart';
import 'package:supasoka/services/subscription_store.dart';

Future<void> _applyUpdatePayload(BuildContext context, Map<String, dynamic>? payload) async {
  if (payload == null) return;
  final store = context.read<ContentStore>();
  await store.applyServerUpdatePayload(payload);
}

Map<String, dynamic> _channelDataForSession(ApiPlaybackSession session, Channel? channel) {
  return {
    'streamUrl': session.streamUrl,
    'stream_url': session.streamUrl,
    'drmType': nativeDrmTypeForSession(session),
    'drm_type': nativeDrmTypeForSession(session),
    'licenseUrl': session.licenseUrl,
    'license_url': session.licenseUrl,
    'drmClearKey': session.clearKeyKidKey,
    'drm_clear_key': session.clearKeyKidKey,
    'clearKeyHex': session.clearKeyKidKey,
    'audioLanguage': session.audioLanguage,
    'audio_language': session.audioLanguage,
    if (channel?.audioLanguage != null) 'channelAudioLanguage': channel!.audioLanguage,
    'headers': playbackHttpHeaders(session.streamUrl),
  };
}

Future<void> _openResolvedPlayback(
  BuildContext context,
  ApiPlaybackSession session, {
  Channel? channel,
}) async {
  final resolved = sessionWithResolvedAudioLanguage(session, channel);
  final channelData = _channelDataForSession(resolved, channel);
  final headers = playbackHttpHeaders(resolved.streamUrl);
  if (headers.isNotEmpty) {
    channelData['headers'] = headers;
  }

  await PlayerPlaybackService.open(
    context: context,
    url: resolved.streamUrl,
    channelId: channel?.id,
    channelName: channel?.name,
    channelData: channelData,
    extractClearKey: clearKeyPayloadFromData,
    normalizeDrm: normalizedDrmType,
    extractToken: playbackTokenFromData,
    extractHeaders: playbackHeadersFromData,
    extractAudioLanguage: playbackAudioLanguageFromData,
  );
}

Future<void> _openQuickFromChannel(BuildContext context, Channel channel) async {
  await _openResolvedPlayback(context, apiSessionFromChannel(channel), channel: channel);
}

Future<void> _refreshPlaybackAfterQuickOpen(Channel channel) async {
  try {
    await resolveChannelPlayback(channel.id, bypassCache: true);
  } catch (_) {}
}

Future<bool> _tryPremiumRecoveryAndPlay(
  BuildContext context,
  Channel channel,
) async {
  final hasPending = await PremiumRecovery.hasRecentPendingPayment();
  if (!hasPending) return false;
  final unlocked = await PremiumRecovery.ensurePremiumUnlocked();
  if (!unlocked) return false;
  invalidatePlaybackCache(channel.id);
  final retry = await resolveChannelPlayback(channel.id, bypassCache: true);
  if (!context.mounted) return true;
  if (retry.code == PlaybackResolveCode.ok && retry.session != null) {
    await _openResolvedPlayback(context, retry.session!, channel: channel);
    return true;
  }
  return false;
}

Future<void> _handlePremiumRequired(
  BuildContext context,
  Channel channel,
) async {
  invalidatePlaybackCache(channel.id);
  unawaited(SubscriptionStore.syncPremiumFromBackend());
  if (SubscriptionStore.isPremiumActiveLocal()) {
    final retry = await resolveChannelPlayback(channel.id, bypassCache: true);
    if (!context.mounted) return;
    if (retry.code == PlaybackResolveCode.ok && retry.session != null) {
      await _openResolvedPlayback(context, retry.session!, channel: channel);
      return;
    }
  }
  if (await _tryPremiumRecoveryAndPlay(context, channel)) return;
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const PaymentScreen()),
  );
}

Future<void> _handlePlaybackResolve(
  BuildContext context,
  Channel channel,
  PlaybackResolveResult resolved,
) async {
  switch (resolved.code) {
    case PlaybackResolveCode.updateRequired:
      await _applyUpdatePayload(context, resolved.updatePayload);
      return;
    case PlaybackResolveCode.premiumRequired:
      await _handlePremiumRequired(context, channel);
      return;
    case PlaybackResolveCode.unavailable:
      final retry = await resolveChannelPlayback(channel.id, bypassCache: true);
      if (!context.mounted) return;
      if (retry.code == PlaybackResolveCode.ok && retry.session != null) {
        await _openResolvedPlayback(context, retry.session!, channel: channel);
        return;
      }
      if (channel.streamUrl.trim().isNotEmpty) {
        await _openQuickFromChannel(context, channel);
        return;
      }
      return;
    case PlaybackResolveCode.ok:
      await _openResolvedPlayback(context, resolved.session!, channel: channel);
  }
}

/// Resolves stream from server (build + premium checks) before opening the player.
Future<void> openChannelPlayback(BuildContext context, int channelId) async {
  final store = context.read<ContentStore>();
  if (store.updateRequired) return;

  final ch = store.channelById(channelId);
  if (ch == null) return;
  await openChannelPlaybackForChannel(context, ch);
}

/// One-tap open — uses cached/list URL immediately; refreshes authority in background.
Future<void> openChannelPlaybackForChannel(BuildContext context, Channel channel) async {
  final store = context.read<ContentStore>();
  if (store.updateRequired) return;

  if (!channel.free) {
    unawaited(SubscriptionStore.syncPremiumFromBackend());
  }

  final cached = peekCachedPlayback(channel.id);
  if (cached != null && cached.streamUrl.trim().isNotEmpty) {
    await _openResolvedPlayback(context, cached, channel: channel);
    unawaited(resolveChannelPlayback(channel.id, bypassCache: !channel.free));
    return;
  }

  final listUrl = channel.streamUrl.trim();
  if (listUrl.isNotEmpty) {
    await _openQuickFromChannel(context, channel);
    unawaited(_refreshPlaybackAfterQuickOpen(channel));
    return;
  }

  final resolved = await resolveChannelPlayback(
    channel.id,
    bypassCache: !channel.free,
  );
  if (!context.mounted) return;
  await _handlePlaybackResolve(context, channel, resolved);
}
