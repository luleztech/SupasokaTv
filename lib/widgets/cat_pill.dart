import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/theme/brand_palette.dart';

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

HomeSectionStyle _pillStyle(String key) => HomeSectionStyle.forCategoryKey(key);

/// Horizontal category tab strip for the home screen.
class CatPillStrip extends StatelessWidget {
  const CatPillStrip({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (context, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => children[i],
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
    final style = _pillStyle(categoryKey);
    final tint = style.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPress,
        borderRadius: BorderRadius.circular(20),
        splashColor: tint.withValues(alpha: 0.18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(active ? 14 : 12, 10, active ? 18 : 16, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: active ? style.accentGradient : null,
            color: active ? null : BrandPalette.bgMid.withValues(alpha: 0.85),
            border: Border.all(
              color: active
                  ? BrandPalette.white.withValues(alpha: 0.22)
                  : tint.withValues(alpha: 0.28),
              width: active ? 1.2 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: active
                      ? BrandPalette.white.withValues(alpha: 0.18)
                      : tint.withValues(alpha: 0.12),
                  border: Border.all(
                    color: active
                        ? BrandPalette.white.withValues(alpha: 0.25)
                        : tint.withValues(alpha: 0.3),
                  ),
                ),
                alignment: Alignment.center,
                child: active
                    ? Text(style.emoji, style: const TextStyle(fontSize: 13, height: 1))
                    : Icon(pillIcon(icon), size: 13, color: tint),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: inter(active ? 12.5 : 12, weight: active ? FontWeight.w800 : FontWeight.w600).copyWith(
                  color: active ? BrandPalette.white : BrandPalette.white.withValues(alpha: 0.82),
                  letterSpacing: 0.2,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
