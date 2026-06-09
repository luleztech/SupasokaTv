import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';

IconData pillIcon(String name) {
  switch (name) {
    case 'flame-outline':
      return Ionicons.flame_outline;
    case 'football-outline':
      return Ionicons.football_outline;
    case 'film-outline':
      return Ionicons.film_outline;
    case 'trophy-outline':
      return Ionicons.trophy_outline;
    case 'musical-notes-outline':
      return Ionicons.musical_notes_outline;
    case 'newspaper-outline':
      return Ionicons.newspaper_outline;
    case 'tv-outline':
      return Ionicons.tv_outline;
    default:
      return Ionicons.flame_outline;
  }
}

({String emoji, Color tint}) _categoryAccent(String key, AppThemeColors t) {
  switch (key) {
    case 'all':
      return (emoji: '🔥', tint: t.accent);
    case 'football':
    case 'mpira':
    case 'sports':
      return (emoji: '⚽', tint: const Color(0xFF4ade80));
    case 'movies':
    case 'tamthilia':
      return (emoji: '🎬', tint: const Color(0xFFc084fc));
    case 'news':
    case 'habari':
      return (emoji: '📰', tint: const Color(0xFF38bdf8));
    case 'entertainment':
      return (emoji: '🎵', tint: const Color(0xFFf472b6));
    default:
      return (emoji: '📺', tint: t.accent2);
  }
}

/// Horizontal category tab strip for the home screen.
class CatPillStrip extends StatelessWidget {
  const CatPillStrip({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: t.card.withValues(alpha: 0.35),
        border: Border.all(color: t.border.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: children.length,
              separatorBuilder: (context, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) => children[i],
            ),
          ],
        ),
      ),
    );
  }
}

class CatPill extends StatelessWidget {
  const CatPill({
    super.key,
    required this.label,
    required this.icon,
    required this.categoryKey,
    required this.active,
    required this.onPress,
  });

  final String label;
  final String icon;
  final String categoryKey;
  final bool active;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final style = _categoryAccent(categoryKey, t);
    final tint = style.tint;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPress,
        borderRadius: BorderRadius.circular(14),
        splashColor: tint.withValues(alpha: 0.2),
        highlightColor: tint.withValues(alpha: 0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(active ? 10 : 8, 6, active ? 14 : 12, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: active
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tint,
                      Color.lerp(tint, t.accent2, 0.55)!,
                    ],
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      t.bg2.withValues(alpha: 0.72),
                      t.card.withValues(alpha: 0.45),
                    ],
                  ),
            border: Border.all(
              color: active ? Colors.white.withValues(alpha: 0.28) : tint.withValues(alpha: 0.28),
              width: active ? 1.2 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.42),
                      blurRadius: 14,
                      spreadRadius: -3,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: active
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.28),
                            Colors.black.withValues(alpha: 0.12),
                          ],
                        )
                      : null,
                  color: active ? null : tint.withValues(alpha: 0.12),
                  border: Border.all(
                    color: active ? Colors.white.withValues(alpha: 0.22) : tint.withValues(alpha: 0.35),
                  ),
                ),
                alignment: Alignment.center,
                child: active
                    ? Text(style.emoji, style: const TextStyle(fontSize: 14, height: 1))
                    : Icon(
                        pillIcon(icon),
                        size: 13,
                        color: tint.withValues(alpha: 0.95),
                      ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: inter(active ? 13 : 12.5, weight: active ? FontWeight.w800 : FontWeight.w600).copyWith(
                      letterSpacing: active ? 0.2 : 0.05,
                      color: active ? Colors.white : t.text.withValues(alpha: 0.88),
                      height: 1,
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: 18,
                      height: 2.5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: Colors.white.withValues(alpha: 0.85),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.35),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
