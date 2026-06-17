import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/player/playback_http_headers.dart';
import 'package:supasoka/screens/payment_screen.dart';
import 'package:supasoka/screens/player_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/native_android_player.dart';
import 'package:supasoka/services/playback_service.dart';
import 'package:supasoka/services/premium_recovery.dart';
import 'package:supasoka/services/subscription_store.dart';

String nativeDrmTypeFor(Channel channel) {
  final drm = channel.drm.trim().toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');
  switch (drm) {
    case 'clearkey':
      return channel.clearKeyKidKey.trim().isEmpty ? 'NONE' : 'CLEARKEY';
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

Future<void> _applyUpdatePayload(BuildContext context, Map<String, dynamic>? payload) async {
  if (payload == null) return;
  final store = context.read<ContentStore>();
  await store.applyServerUpdatePayload(payload);
}

Future<bool> _openResolvedPlayback(BuildContext context, PlaybackSession session) async {
  if (NativeAndroidPlayer.supported) {
    await NativeAndroidPlayer.open(
      url: session.streamUrl,
      licenseUrl: session.licenseUrl.trim(),
      drmType: nativeDrmTypeForSession(session),
      clearKeyHex: session.clearKeyKidKey.trim(),
      headers: playbackHttpHeaders(session.streamUrl),
    );
    return true;
  }
  if (!context.mounted) return false;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        channelId: 0,
        playbackSession: session,
      ),
    ),
  );
  return true;
}

/// Resolves stream from server (build + premium checks) before opening the player.
Future<void> openChannelPlayback(BuildContext context, int channelId) async {
  final store = context.read<ContentStore>();
  if (store.updateRequired) return;

  final ch = store.channelById(channelId);
  if (ch == null) {
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => PlayerScreen(channelId: channelId)),
    );
    return;
  }
  await openChannelPlaybackForChannel(context, ch);
}

Future<void> openChannelPlaybackForChannel(BuildContext context, Channel channel) async {
  final store = context.read<ContentStore>();
  if (store.updateRequired) return;

  if (!channel.free) {
    await SubscriptionStore.syncPremiumFromBackend();
    invalidatePlaybackCache(channel.id);
  }

  final resolved = await resolveChannelPlayback(
    channel.id,
    bypassCache: !channel.free,
  );
  if (!context.mounted) return;

  switch (resolved.code) {
    case PlaybackResolveCode.updateRequired:
      await _applyUpdatePayload(context, resolved.updatePayload);
      return;
    case PlaybackResolveCode.premiumRequired:
      invalidatePlaybackCache(channel.id);
      await SubscriptionStore.syncPremiumFromBackend();
      if (SubscriptionStore.isPremiumActiveLocal()) {
        final retry = await resolveChannelPlayback(channel.id, bypassCache: true);
        if (!context.mounted) return;
        if (retry.code == PlaybackResolveCode.ok) {
          await _openResolvedPlayback(context, retry.session!);
          return;
        }
      }
      final hasPending = await PremiumRecovery.hasRecentPendingPayment();
      if (hasPending) {
        final unlocked = await PremiumRecovery.ensurePremiumUnlocked();
        if (unlocked) {
          invalidatePlaybackCache(channel.id);
          final retry = await resolveChannelPlayback(channel.id, bypassCache: true);
          if (!context.mounted) return;
          if (retry.code == PlaybackResolveCode.ok) {
            await _openResolvedPlayback(context, retry.session!);
            return;
          }
        }
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const PaymentScreen()),
      );
      return;
    case PlaybackResolveCode.unavailable:
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => PlayerScreen(channelId: channel.id)),
      );
      return;
    case PlaybackResolveCode.ok:
      await _openResolvedPlayback(context, resolved.session!);
  }
}
