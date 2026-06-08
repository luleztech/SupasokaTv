import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/player/playback_http_headers.dart';
import 'package:supasoka/screens/player_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/native_android_player.dart';

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

/// Android: opens native player directly (skips Flutter [PlayerScreen]).
/// Other platforms: [PlayerScreen].
Future<void> openChannelPlayback(BuildContext context, int channelId) async {
  final ch = context.read<ContentStore>().channelById(channelId);
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
  final url = channel.streamUrl.trim();
  if (NativeAndroidPlayer.supported && url.isNotEmpty) {
    await NativeAndroidPlayer.open(
      url: url,
      licenseUrl: channel.licenseUrl.trim(),
      drmType: nativeDrmTypeFor(channel),
      clearKeyHex: channel.clearKeyKidKey.trim(),
      headers: playbackHttpHeaders(url),
    );
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => PlayerScreen(channelId: channel.id)),
  );
}
