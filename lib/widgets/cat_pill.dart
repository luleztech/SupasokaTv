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
    default:
      return Ionicons.flame_outline;
  }
}

class CatPill extends StatelessWidget {
  const CatPill({super.key, required this.label, required this.icon, required this.active, required this.onPress});

  final String label;
  final String icon;
  final bool active;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPress,
        borderRadius: BorderRadius.circular(99),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: active ? LinearGradient(colors: [t.accent, t.accent2]) : null,
            color: active ? null : t.card,
            border: active ? null : Border.all(color: t.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(pillIcon(icon), size: 13, color: active ? Colors.white : t.text2),
              const SizedBox(width: 6),
              Text(
                label,
                style: rajdhani(13, weight: FontWeight.w600).copyWith(
                  letterSpacing: 0.5,
                  color: active ? Colors.white : t.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
