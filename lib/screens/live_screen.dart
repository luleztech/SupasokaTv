import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/screens/payment_screen.dart';
import 'package:supasoka/screens/player_screen.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/widgets/app_header.dart';
import 'package:supasoka/widgets/channel_card.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  void _openChannel(BuildContext context, int channelId) {
    final ch = channelById(channelId);
    if (ch != null && !ch.free) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PaymentScreen()));
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerScreen(channelId: channelId)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final w = MediaQuery.sizeOf(context).width;
    final cellW = (w - 32 - 12) / 2;

    return ColoredBox(
      color: t.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(title: 'Live', subtitle: '● ON AIR'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'LIVE ', style: orbitron(13, weight: FontWeight.w700).copyWith(color: t.text)),
                      TextSpan(text: 'NOW', style: orbitron(13, weight: FontWeight.w700).copyWith(color: const Color(0xFFff1744))),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text('Tap any channel to watch live', style: rajdhani(12).copyWith(color: t.text2)),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: cellW / kChannelCardLiveGridHeight,
              ),
              itemCount: kLiveMatches.length,
              itemBuilder: (context, i) {
                final m = kLiveMatches[i];
                final channelId = m.id % kChannels.length;
                final ch = channelById(channelId) ?? kChannels.first;
                return ChannelCard(
                  channel: ch,
                  onPress: () => _openChannel(context, channelId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
