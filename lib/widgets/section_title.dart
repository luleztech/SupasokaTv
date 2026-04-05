import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.main, this.accent});

  final String main;
  final String? accent;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: RichText(
        text: TextSpan(
          style: orbitron(13).copyWith(color: t.text, letterSpacing: 2),
          children: [
            TextSpan(text: '$main '),
            if (accent != null) TextSpan(text: accent, style: TextStyle(color: t.accent)),
          ],
        ),
      ),
    );
  }
}
