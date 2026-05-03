import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/screens/payment_screen.dart';
import 'package:supasoka/screens/player_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/widgets/app_header.dart';
import 'package:supasoka/widgets/safe_network_image.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  void _openChannel(BuildContext context, int channelId) {
    final store = context.read<ContentStore>();
    final ch = store.channelById(channelId);
    final isPremium = SubscriptionStore.premiumUntilNotifier.value?.isAfter(DateTime.now()) ?? false;
    if (ch != null && !ch.free && !isPremium) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PaymentScreen()));
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerScreen(channelId: channelId)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final store = context.watch<ContentStore>();
    final w = MediaQuery.sizeOf(context).width;
    final cellW = (w - 32 - 12) / 2;
    final bannerH = cellW * 9 / 16;
    /// Match tiles are 16:9 only — title/channel overlay inside the poster ([_LiveMatchCard]).
    final tileH = bannerH;
    final matches = store.liveMatches;

    return ColoredBox(
      color: t.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppHeader(title: 'Live', subtitle: '● ON AIR'),
          Expanded(
            child: RefreshIndicator(
              color: t.accent,
              onRefresh: () => context.read<ContentStore>().refresh(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  /// Approximate height of [_liveNowHeading] so empty state centers in remaining viewport.
                  const headingReserve = 56.0;

                  Widget liveHeading() {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: 'LIVE ', style: orbitron(13, weight: FontWeight.w700).copyWith(color: t.text)),
                                TextSpan(text: 'NOW', style: orbitron(13, weight: FontWeight.w700).copyWith(color: t.accent)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap any channel to watch live',
                            style: rajdhani(12).copyWith(color: t.text2, height: 1.05),
                          ),
                        ],
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          liveHeading(),
                          if (matches.isEmpty)
                            SizedBox(
                              height: math.max(120.0, constraints.maxHeight - headingReserve),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Center(
                                  child: Text(
                                    'Hakuna mechi za moja kwa moja zilizo orodheshwa.',
                                    textAlign: TextAlign.center,
                                    style: rajdhani(14, weight: FontWeight.w600).copyWith(color: t.text2),
                                  ),
                                ),
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                              child: GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: cellW / tileH,
                                ),
                                itemCount: matches.length,
                                itemBuilder: (context, i) {
                                  final m = matches[i];
                                  final channelId = m.channelId;
                                  final ch = store.channelById(channelId);
                                  if (ch == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return _LiveMatchCard(
                                    match: m,
                                    channel: ch,
                                    onPress: () => _openChannel(context, channelId),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveMatchCard extends StatelessWidget {
  const _LiveMatchCard({required this.match, required this.channel, required this.onPress});

  final LiveMatch match;
  final Channel channel;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final posterUrl = match.img.trim().isNotEmpty ? match.img : channel.img;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPress,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: t.card),
                  SafeNetworkImage(
                    imageUrl: posterUrl,
                    fit: BoxFit.cover,
                    placeholderColor: t.card,
                    alignment: Alignment.center,
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.45, 1.0],
                          colors: [
                            Colors.black.withValues(alpha: 0.1),
                            Colors.black.withValues(alpha: 0.22),
                            Colors.black.withValues(alpha: 0.82),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: t.red,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'LIVE',
                            style: orbitron(9, weight: FontWeight.w900).copyWith(
                              color: Colors.white,
                              letterSpacing: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (match.sport.trim().isNotEmpty)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                        ),
                        child: Text(
                          match.sport.toUpperCase(),
                          style: rajdhani(10, weight: FontWeight.w700).copyWith(
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.88),
                          ],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 15,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                match.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: rajdhani(12, weight: FontWeight.w700).copyWith(
                                  color: Colors.white,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(Ionicons.tv_outline, size: 14, color: t.accent),
                              const SizedBox(width: 5),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  channel.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: rajdhani(11, weight: FontWeight.w600).copyWith(
                                    color: Colors.white.withValues(alpha: 0.88),
                                  ),
                                ),
                              ),
                              if (match.matchTime != null && match.matchTime!.trim().isNotEmpty)
                                Flexible(
                                  flex: 2,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Ionicons.time_outline, size: 12, color: Colors.white.withValues(alpha: 0.65)),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          match.matchTime!.trim(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.end,
                                          style: rajdhani(10, weight: FontWeight.w600).copyWith(
                                            color: Colors.white.withValues(alpha: 0.75),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
