import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';

/// Used by 2-column grids: `childAspectRatio: cellW / kChannelCardGridHeight`.
const double kChannelCardGridHeight = 280;

/// Live tab uses standard channel tiles (not the tall poster grid).
const double kChannelCardLiveGridHeight = 170;

const Map<String, String> kCatLabel = {
  'football': 'Football',
  'movies': 'Movies',
  'sports': 'Sports',
  'entertainment': 'Entertainment',
  'news': 'News',
};

IconData catIconFor(String cat) {
  switch (cat) {
    case 'football':
      return Ionicons.football_outline;
    case 'movies':
      return Ionicons.film_outline;
    case 'sports':
      return Ionicons.trophy_outline;
    case 'entertainment':
      return Ionicons.musical_notes_outline;
    case 'news':
      return Ionicons.newspaper_outline;
    default:
      return Ionicons.tv_outline;
  }
}

class ChannelCard extends StatefulWidget {
  const ChannelCard({super.key, required this.channel, required this.onPress});

  final Channel channel;
  final VoidCallback onPress;

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final borderColor = ch.free ? const Color.fromRGBO(0, 229, 255, 0.35) : const Color.fromRGBO(255, 215, 0, 0.45);

    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onPress,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(imageUrl: ch.img, fit: BoxFit.cover),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 36, 10, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color.fromRGBO(0, 0, 0, 0.88)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: rajdhani(13, weight: FontWeight.w700).copyWith(color: Colors.white, height: 1.2),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(catIconFor(ch.cat), size: 10, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            kCatLabel[ch.cat] ?? ch.cat,
                            style: rajdhani(10, weight: FontWeight.w600).copyWith(
                              color: Colors.white.withValues(alpha: 0.7),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(top: 8, left: 8, child: _LiveBadge()),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ch.free ? const Color.fromRGBO(0, 230, 118, 0.92) : const Color.fromRGBO(255, 215, 0, 0.92),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ch.free ? 'FREE' : 'PREMIUM',
                    style: orbitron(8).copyWith(color: Colors.black, letterSpacing: 0.5),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00e5ff).withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
  late final Animation<double> _op = Tween(begin: 0.7, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _op,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFFff1744), borderRadius: BorderRadius.circular(4)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text('LIVE', style: orbitron(8).copyWith(color: Colors.white, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}
