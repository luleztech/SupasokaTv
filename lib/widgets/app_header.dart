import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onSettings,
    this.onSearch,
    this.rightSlot,
    this.leftSlot,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onSettings;
  final VoidCallback? onSearch;
  final Widget? rightSlot;
  final Widget? leftSlot;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final top = MediaQuery.paddingOf(context).top;

    return Container(
      color: t.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: top + 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leftSlot != null) ...[leftSlot!, const SizedBox(width: 10)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [t.accent, t.accent2],
                        ).createShader(bounds),
                        child: Text(
                          title,
                          style: orbitron(22, weight: FontWeight.w900).copyWith(
                            color: Colors.white,
                            letterSpacing: 1,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 1)),
                            ],
                          ),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              width: 14,
                              height: 2,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [t.accent, t.accent2]),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              subtitle!,
                              style: rajdhani(11, weight: FontWeight.w600).copyWith(
                                color: t.text2,
                                letterSpacing: 3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (rightSlot != null) rightSlot!,
                if (onSettings != null)
                  _IconBtn(
                    onTap: onSettings!,
                    child: Icon(Ionicons.settings_outline, size: 17, color: t.text),
                  ),
                if (onSearch != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _IconBtn(
                      onTap: onSearch!,
                      child: Icon(Ionicons.search_outline, size: 17, color: t.text),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Divider(height: 1, thickness: 1, color: t.border.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    return Material(
      color: t.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(width: 38, height: 38, child: Center(child: child)),
      ),
    );
  }
}

class BackBtn extends StatelessWidget {
  const BackBtn({super.key, required this.onPress});

  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPress,
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Center(child: Text('‹', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600))),
        ),
      ),
    );
  }
}
