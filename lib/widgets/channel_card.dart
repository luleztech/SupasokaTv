import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/widgets/safe_network_image.dart';

/// Portrait thumb (3:4) + centered title — must match [AspectRatio] below.
double channelCardCellHeight(double cellWidth) => cellWidth * 4 / 3 + 76;

/// Poster trimmed vs 3:4 — title overlays inside poster; keep in sync with [ChannelCard] `compactGrid`.
const double _kChannelGridPosterTrim = 52;

/// Same computation as [ChannelCard] grid [LayoutBuilder] (must stay in sync).
double _channelGridPosterHeight(double cellWidth) =>
    (cellWidth * 4 / 3 - _kChannelGridPosterTrim).clamp(96.0, double.infinity);

/// Channels tab grid cell height — poster + tiny slack for float / title shadow paint.
double channelGridCellHeight(double cellWidth) => _channelGridPosterHeight(cellWidth) + 1.5;

/// Home horizontal rails — poster + slack (name overlay inside thumb).
double channelRailCellHeight(double tileWidth) => tileWidth * 4 / 3 + 1.5;

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

/// Supastream-style channel tile: 16:9 art, meta below, zinc border, brand-red LIVE.
class ChannelCard extends StatefulWidget {
  const ChannelCard({
    super.key,
    required this.channel,
    required this.onPress,
    this.locked = false,
    this.width,
    this.compactGrid = false,
  });

  final Channel channel;
  final VoidCallback onPress;
  final bool locked;
  /// When set (e.g. horizontal rails), fixes tile width like `w-44` / `w-56`.
  final double? width;
  /// Channels grid: trimmed poster + title overlay inside thumb ([compactGrid]).
  final bool compactGrid;

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelPoster extends StatelessWidget {
  const _ChannelPoster({
    required this.t,
    required this.ch,
    required this.locked,
    this.titleOverlay = false,
    this.titleOverlayCompact = false,
  });

  final AppThemeColors t;
  final Channel ch;
  final bool locked;
  final bool titleOverlay;
  final bool titleOverlayCompact;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: t.card),
          SafeNetworkImage(imageUrl: ch.img, fit: BoxFit.cover, placeholderColor: t.card),
          if (titleOverlay)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRect(
                child: _ChannelNameOverlay(
                  name: ch.name,
                  compact: titleOverlayCompact,
                ),
              ),
            ),
          Positioned(
            top: 6,
            left: 6,
            child: _LivePill(colors: t),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: _AccessBadge(colors: t, channel: ch, lockedForViewer: locked),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x8027272a)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom gradient scrim + channel title (grid/rail).
class _ChannelNameOverlay extends StatelessWidget {
  const _ChannelNameOverlay({required this.name, required this.compact});

  final String name;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fs = compact ? 10.0 : 12.0;
    final lines = compact ? 1 : 2;
    final pad = compact
        ? const EdgeInsets.fromLTRB(8, 18, 8, 8)
        : const EdgeInsets.fromLTRB(10, 22, 10, 10);

    return Container(
      width: double.infinity,
      padding: pad,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.2, 0.55, 1.0],
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.42),
            Colors.black.withValues(alpha: 0.78),
          ],
        ),
      ),
      child: Text(
        name.toUpperCase(),
        textAlign: TextAlign.center,
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
        style: orbitron(fs, weight: FontWeight.w800).copyWith(
          color: Colors.white,
          height: 1.08,
          letterSpacing: compact ? 0.45 : 0.55,
          shadows: [
            Shadow(color: Colors.black.withValues(alpha: 0.88), blurRadius: 12, offset: const Offset(0, 1)),
            Shadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 6, offset: const Offset(0, 1)),
          ],
        ),
      ),
    );
  }
}

class _ChannelCardState extends State<ChannelCard> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final ch = widget.channel;
    final w = widget.width;
    final rail = w != null;
    final grid = widget.compactGrid;
    final titleInsidePoster = grid || rail;
    final gapPoster = rail ? 6.0 : (grid ? 2.0 : 10.0);
    final titleSize = rail ? 13.0 : (grid ? 10.0 : 14.0);
    final titleLines = rail ? 2 : (grid ? 1 : 3);
    final titleHeight = rail ? 1.12 : (grid ? 1.0 : 1.2);
    final titleLetter = rail ? 0.5 : (grid ? 0.5 : 0.6);
    final padH = rail ? 6.0 : 8.0;

    final core = GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.98),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onPress,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (grid)
              LayoutBuilder(
                builder: (context, c) {
                  final cw = c.maxWidth;
                  final posterH = _channelGridPosterHeight(cw);
                  return AspectRatio(
                    aspectRatio: cw / posterH,
                    child: _ChannelPoster(
                      t: t,
                      ch: ch,
                      locked: widget.locked,
                      titleOverlay: true,
                      titleOverlayCompact: true,
                    ),
                  );
                },
              )
            else
              AspectRatio(
                aspectRatio: 3 / 4,
                child: _ChannelPoster(
                  t: t,
                  ch: ch,
                  locked: widget.locked,
                  titleOverlay: rail,
                  titleOverlayCompact: false,
                ),
              ),
            if (!titleInsidePoster) ...[
              SizedBox(height: gapPoster),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      ch.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: titleLines,
                      overflow: TextOverflow.ellipsis,
                      style: orbitron(titleSize, weight: FontWeight.w800).copyWith(
                        color: t.text,
                        height: titleHeight,
                        letterSpacing: titleLetter,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (w != null) {
      return SizedBox(width: w, child: core);
    }
    return core;
  }
}

/// FREE, or premium: lock + **imefungwa** (no sub) / **zimefunguliwa** (subscribed).
class _AccessBadge extends StatelessWidget {
  const _AccessBadge({
    required this.colors,
    required this.channel,
    required this.lockedForViewer,
  });

  final AppThemeColors colors;
  final Channel channel;
  final bool lockedForViewer;

  @override
  Widget build(BuildContext context) {
    final t = colors;
    final ch = channel;

    if (ch.free) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF27272a),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Text(
          'FREE',
          style: orbitron(7, weight: FontWeight.w900).copyWith(
            color: const Color(0xFFa1a1aa),
            letterSpacing: 0.8,
          ),
        ),
      );
    }

    if (lockedForViewer) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 118),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.accent.withValues(alpha: 0.85)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Ionicons.lock_closed, size: 11, color: t.accent),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'imefungwa',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: rajdhani(9, weight: FontWeight.w700).copyWith(color: Colors.white, height: 1.05),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 124),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF14532d).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF22c55e).withValues(alpha: 0.45)),
      ),
      child: Text(
        'zimefunguliwa',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: rajdhani(8, weight: FontWeight.w700).copyWith(color: const Color(0xFFbbf7d0), height: 1.05),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.colors});

  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colors.red,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: orbitron(7, weight: FontWeight.w900).copyWith(color: Colors.white, letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}
