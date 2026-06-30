import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/theme/brand_palette.dart';
import 'package:supasoka/widgets/safe_network_image.dart';

/// 16:9 poster + title row below.
double channelCardCellHeight(double cellWidth) => cellWidth * 9 / 16 + 44;

double _channelGridPosterHeight(double cellWidth) => cellWidth * 9 / 16;

double channelGridCellHeight(double cellWidth) => _channelGridPosterHeight(cellWidth) + 52;

double channelRailCellHeight(double tileWidth) => tileWidth * 9 / 16 + 44;

double channelHomeRailCellHeight(double tileWidth) => channelRailCellHeight(tileWidth);

const Map<String, String> kCatLabel = {
  'football': 'Football',
  'movies': 'Movies',
  'sports': 'Sports',
  'entertainment': 'Entertainment',
  'news': 'News',
  'mpira': 'Mpira',
  'habari': 'Habari',
  'tamthilia': 'Tamthilia',
};

String categoryPillLabel(String cat) {
  if (cat.isEmpty) return cat;
  return kCatLabel[cat] ?? '${cat[0].toUpperCase()}${cat.substring(1).toLowerCase()}';
}

String categoryPillIconName(String cat) {
  switch (cat) {
    case 'all':
      return 'flame-outline';
    case 'football':
    case 'mpira':
    case 'sports':
      return 'football-outline';
    case 'movies':
    case 'tamthilia':
      return 'film-outline';
    case 'entertainment':
      return 'musical-notes-outline';
    case 'news':
    case 'habari':
      return 'newspaper-outline';
    default:
      return 'tv-outline';
  }
}

List<CategoryItem> buildCategoryPills(List<Channel> channels) {
  final cats = channels.map((c) => c.cat).toSet().toList()..sort();
  return [
    const CategoryItem(key: 'all', label: 'All', icon: 'flame-outline'),
    ...cats.map(
      (k) => CategoryItem(
        key: k,
        label: categoryPillLabel(k),
        icon: categoryPillIconName(k),
      ),
    ),
  ];
}

IconData catIconFor(String cat) {
  switch (cat) {
    case 'football':
    case 'mpira':
      return Ionicons.football_outline;
    case 'movies':
    case 'tamthilia':
      return Ionicons.film_outline;
    case 'sports':
      return Ionicons.trophy_outline;
    case 'entertainment':
      return Ionicons.musical_notes_outline;
    case 'news':
    case 'habari':
      return Ionicons.newspaper_outline;
    default:
      return Ionicons.tv_outline;
  }
}

class ChannelCard extends StatefulWidget {
  const ChannelCard({
    super.key,
    required this.channel,
    required this.onPress,
    this.locked = false,
    this.width,
    this.posterHeight,
    this.compactGrid = false,
    this.railPosterHeightDelta = 0,
  });

  final Channel channel;
  final VoidCallback onPress;
  final bool locked;
  final double? width;
  final double? posterHeight;
  final bool compactGrid;
  final double railPosterHeightDelta;

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final w = widget.width;
    final resolvedPosterHeight = widget.posterHeight ??
        (w != null ? w * 9 / 16 + widget.railPosterHeightDelta : null);

    final core = GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onPress,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (resolvedPosterHeight != null)
              SizedBox(
                height: resolvedPosterHeight,
                child: _ChannelPoster(ch: ch, locked: widget.locked),
              )
            else
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _ChannelPoster(ch: ch, locked: widget.locked),
              ),
            const SizedBox(height: 6),
            Text(
              ch.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: rajdhani(11, weight: FontWeight.w700).copyWith(
                color: BrandPalette.white.withValues(alpha: 0.88),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );

    if (w != null) return SizedBox(width: w, child: core);
    return core;
  }
}

class _ChannelPoster extends StatelessWidget {
  const _ChannelPoster({required this.ch, required this.locked});

  final Channel ch;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: BrandPalette.bgMid),
          Positioned.fill(
            child: SafeNetworkImage(
              imageUrl: ch.img,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              placeholderColor: BrandPalette.bgMid,
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: const DecoratedBox(decoration: BoxDecoration(gradient: BrandPalette.activeGradient)),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: _AccessBadge(channel: ch, lockedForViewer: locked),
          ),
          if (locked)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: BrandPalette.bgDeep.withValues(alpha: 0.45)),
                child: const Center(
                  child: Icon(Ionicons.lock_closed, color: BrandPalette.white, size: 22),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BrandPalette.white.withValues(alpha: 0.1)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessBadge extends StatelessWidget {
  const _AccessBadge({required this.channel, required this.lockedForViewer});

  final Channel channel;
  final bool lockedForViewer;

  @override
  Widget build(BuildContext context) {
    if (channel.free) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: BrandPalette.bgDeep.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: BrandPalette.accent.withValues(alpha: 0.5)),
        ),
        child: Text(
          'BURE',
          style: orbitron(6.5, weight: FontWeight.w900).copyWith(
            color: BrandPalette.accent,
            letterSpacing: 0.6,
          ),
        ),
      );
    }

    if (lockedForViewer) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: BrandPalette.bgDeep.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: BrandPalette.accentWarm.withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Ionicons.lock_closed, size: 10, color: BrandPalette.accentWarm),
            const SizedBox(width: 3),
            Text(
              'FUNGA',
              style: orbitron(6, weight: FontWeight.w800).copyWith(color: BrandPalette.accentWarm),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: BrandPalette.accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BrandPalette.accent.withValues(alpha: 0.55)),
      ),
      child: Text(
        'OPEN',
        style: orbitron(6, weight: FontWeight.w800).copyWith(color: BrandPalette.accent),
      ),
    );
  }
}

/// Vertical poster card for horizontal "newly added" rails.
class ChannelPosterCard extends StatefulWidget {
  const ChannelPosterCard({
    super.key,
    required this.channel,
    required this.onPress,
    this.locked = false,
    required this.width,
  });

  final Channel channel;
  final VoidCallback onPress;
  final bool locked;
  final double width;

  @override
  State<ChannelPosterCard> createState() => _ChannelPosterCardState();
}

class _ChannelPosterCardState extends State<ChannelPosterCard> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onPress,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: widget.width,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: BrandPalette.bgMid),
                      Positioned.fill(
                        child: SafeNetworkImage(
                          imageUrl: ch.img,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          placeholderColor: BrandPalette.bgMid,
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              BrandPalette.bgDeep.withValues(alpha: 0.75),
                            ],
                          ),
                        ),
                      ),
                      if (widget.locked)
                        ColoredBox(color: BrandPalette.bgDeep.withValues(alpha: 0.45)),
                    ],
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      if (!ch.free)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: BrandPalette.accent.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: BrandPalette.accent.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            '★ PREMIUM',
                            style: orbitron(6, weight: FontWeight.w800).copyWith(color: BrandPalette.accent),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 10,
                  child: Text(
                    ch.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: rajdhani(11, weight: FontWeight.w700).copyWith(
                      color: BrandPalette.white,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
