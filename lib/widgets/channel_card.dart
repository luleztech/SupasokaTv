import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/theme/brand_palette.dart';
import 'package:supasoka/widgets/pro_shimmer.dart';
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

/// Rich palette for auto-cycling aurora glow on channel tiles.
const _kAuroraGlowColors = [
  Color(0xFF38BDF8),
  Color(0xFF22D3EE),
  Color(0xFF2DD4BF),
  Color(0xFF34D399),
  Color(0xFF4ADE80),
  Color(0xFFA3E635),
  Color(0xFFFACC15),
  Color(0xFFFBBF24),
  Color(0xFFFB923C),
  Color(0xFFF59E0B),
  Color(0xFFFB7185),
  Color(0xFFF472B6),
  Color(0xFFE879F9),
  Color(0xFFC084FC),
  Color(0xFFA78BFA),
  Color(0xFF818CF8),
  Color(0xFF60A5FA),
  Color(0xFF0EA5E9),
  Color(0xFFEF4444),
  Color(0xFF14B8A6),
];

/// Skeleton channel tile with aurora glow + shimmer while catalog/images load.
class ChannelCardSkeleton extends StatelessWidget {
  const ChannelCardSkeleton({
    super.key,
    this.width,
    this.posterHeight,
    this.seed = 0,
    this.showTitle = true,
  });

  final double? width;
  final double? posterHeight;
  final int seed;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final w = width;
    final resolvedPosterHeight = posterHeight ?? (w != null ? w * 9 / 16 : null);
    final core = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _AuroraGlowFrame(
          seed: seed,
          borderRadius: 14,
          boosted: true,
          child: resolvedPosterHeight != null
              ? SizedBox(
                  height: resolvedPosterHeight,
                  child: const _ChannelPosterPlaceholder(),
                )
              : const AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _ChannelPosterPlaceholder(),
                ),
        ),
        if (showTitle) ...[
          const SizedBox(height: 4),
          Center(
            child: ProShimmer(
              child: Container(
                height: 10,
                width: w != null ? w * 0.55 : 72,
                decoration: BoxDecoration(
                  color: BrandPalette.bgMid,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ],
    );
    if (w != null) return SizedBox(width: w, child: core);
    return core;
  }
}

class _ChannelPosterPlaceholder extends StatelessWidget {
  const _ChannelPosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ProShimmer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: BrandPalette.bgMid),
            Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: BrandPalette.accent.withValues(alpha: 0.9),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: BrandPalette.white.withValues(alpha: 0.08)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsing, color-shifting outer glow behind channel posters.
class _AuroraGlowFrame extends StatefulWidget {
  const _AuroraGlowFrame({
    required this.seed,
    required this.borderRadius,
    required this.child,
    this.boosted = false,
  });

  final int seed;
  final double borderRadius;
  final Widget child;
  final bool boosted;

  @override
  State<_AuroraGlowFrame> createState() => _AuroraGlowFrameState();
}

class _AuroraGlowFrameState extends State<_AuroraGlowFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final double _phase;
  late final double _colorDrift;

  @override
  void initState() {
    super.initState();
    final s = widget.seed.abs();
    _phase = (s % 997) / 997;
    _colorDrift = 0.85 + (s % 11) * 0.07;
    _pulse = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 2200 + (s % 9) * 260),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color _colorAt(double t) {
    final colors = _kAuroraGlowColors;
    final scaled = (t * colors.length) % colors.length;
    final i = scaled.floor() % colors.length;
    final j = (i + 1) % colors.length;
    final local = scaled - scaled.floor();
    return Color.lerp(colors[i], colors[j], local)!;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final wave = Curves.easeInOut.transform(_pulse.value);
        final breathe = 0.42 + wave * 0.58;
        final boost = widget.boosted ? 1.2 : 1.0;
        final colorT = (_pulse.value * _colorDrift + _phase) % 1.0;
        final primary = _colorAt(colorT);
        final secondary = _colorAt((colorT + 0.31) % 1.0);

        final outerBlur = (1.5 + breathe * 2.5) * boost;
        final midBlur = (1 + breathe * 1.5) * boost;
        final spread = breathe * 0.2 * boost;
        final lift = breathe * 0.5;
        final alphaBoost = widget.boosted ? 1.15 : 1.0;

        return Container(
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius + 1),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: (0.05 + breathe * 0.1) * alphaBoost),
                blurRadius: outerBlur,
                spreadRadius: spread * 0.5,
                offset: Offset(0, lift * 0.25),
              ),
              BoxShadow(
                color: secondary.withValues(alpha: (0.04 + breathe * 0.08) * alphaBoost),
                blurRadius: midBlur,
                spreadRadius: spread * 0.25,
                offset: Offset(math.sin(wave * math.pi * 2) * 0.5, lift * 0.35),
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
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
  bool _imageLoading = true;

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
            _AuroraGlowFrame(
              seed: ch.id,
              borderRadius: 14,
              boosted: _imageLoading,
              child: resolvedPosterHeight != null
                  ? SizedBox(
                      height: resolvedPosterHeight,
                      child: _ChannelPoster(
                        ch: ch,
                        locked: widget.locked,
                        imageLoading: _imageLoading,
                        onImageLoadingChanged: (loading) {
                          if (_imageLoading != loading) {
                            setState(() => _imageLoading = loading);
                          }
                        },
                      ),
                    )
                  : AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _ChannelPoster(
                        ch: ch,
                        locked: widget.locked,
                        imageLoading: _imageLoading,
                        onImageLoadingChanged: (loading) {
                          if (_imageLoading != loading) {
                            setState(() => _imageLoading = loading);
                          }
                        },
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              ch.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
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
  const _ChannelPoster({
    required this.ch,
    required this.locked,
    required this.imageLoading,
    this.onImageLoadingChanged,
  });

  final Channel ch;
  final bool locked;
  final bool imageLoading;
  final ValueChanged<bool>? onImageLoadingChanged;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: SafeNetworkImage(
              imageUrl: ch.img,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              placeholderColor: BrandPalette.bgDeep,
              onLoadingChanged: onImageLoadingChanged,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: imageLoading ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: BrandPalette.accent.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ),
            ),
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
              'MALIPO',
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
  bool _imageLoading = true;

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
          child: _AuroraGlowFrame(
            seed: ch.id,
            borderRadius: 18,
            boosted: _imageLoading,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: SafeNetworkImage(
                            imageUrl: ch.img,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            placeholderColor: BrandPalette.bgDeep,
                            onLoadingChanged: (loading) {
                              if (_imageLoading != loading) {
                                setState(() => _imageLoading = loading);
                              }
                            },
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _imageLoading ? 1 : 0,
                              duration: const Duration(milliseconds: 220),
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: BrandPalette.accent.withValues(alpha: 0.92),
                                  ),
                                ),
                              ),
                            ),
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
                      textAlign: TextAlign.center,
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
      ),
    );
  }
}
