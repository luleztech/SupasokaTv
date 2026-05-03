import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';

/// Category row title — Supastream blue bar + uppercase label.
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.main, this.accent, this.trailing});

  final String main;
  final String? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: rajdhani(11, weight: FontWeight.w800).copyWith(
                  color: const Color(0xFFa1a1aa),
                  letterSpacing: 1.2,
                  fontStyle: FontStyle.italic,
                  decoration: TextDecoration.none,
                ),
                children: [
                  TextSpan(text: '$main${accent != null ? ' ' : ''}'),
                  if (accent != null)
                    TextSpan(
                      text: accent,
                      style: TextStyle(color: t.accent, decoration: TextDecoration.none),
                    ),
                ],
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
