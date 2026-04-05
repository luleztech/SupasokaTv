import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/screens/channels_screen.dart';
import 'package:supasoka/screens/home_screen.dart';
import 'package:supasoka/screens/live_screen.dart';
import 'package:supasoka/screens/payment_screen.dart';
import 'package:supasoka/screens/profile_screen.dart';
import 'package:supasoka/theme/app_theme.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppNav>();
    final t = context.watch<ThemeController>().colors;
    final refreshing = context.watch<ContentStore>().refreshing;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: t.bg1,
      body: Column(
        children: [
          if (refreshing)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: t.border.withValues(alpha: 0.35),
              color: t.accent,
            ),
          Expanded(
            child: IndexedStack(
              index: nav.currentTab,
              children: const [
                HomeScreen(),
                ChannelsScreen(),
                LiveScreen(),
                PaymentScreen(),
                ProfileScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: t.navBg,
          border: Border(top: BorderSide(color: t.border)),
        ),
        padding: EdgeInsets.only(top: 8, bottom: bottom + 4),
        child: Row(
          children: [
            _TabButton(i: 0, label: 'Home', outline: Ionicons.home_outline, solid: Ionicons.home, selected: nav.currentTab == 0),
            _TabButton(i: 1, label: 'Vituo', outline: Ionicons.tv_outline, solid: Ionicons.tv, selected: nav.currentTab == 1),
            _TabButton(i: 2, label: 'Live', outline: Ionicons.radio_outline, solid: Ionicons.radio, selected: nav.currentTab == 2),
            _TabButton(i: 3, label: 'Malipo', outline: Ionicons.card_outline, solid: Ionicons.card, selected: nav.currentTab == 3),
            _TabButton(i: 4, label: 'Akaunti', outline: Ionicons.person_outline, solid: Ionicons.person, selected: nav.currentTab == 4),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.i,
    required this.label,
    required this.outline,
    required this.solid,
    required this.selected,
  });

  final int i;
  final String label;
  final IconData outline;
  final IconData solid;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final icon = selected ? solid : outline;

    return Expanded(
      child: InkWell(
        onTap: () {
          final changed = context.read<AppNav>().setTab(i);
          if (changed) unawaited(context.read<ContentStore>().refresh());
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 36,
              transform: selected ? (Matrix4.identity()..translate(0.0, -4.0)) : Matrix4.identity(),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: selected ? LinearGradient(colors: [t.accent, t.accent2]) : null,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 22, color: selected ? Colors.black : t.text2),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: selected ? t.accent : t.text2,
              ),
            ),
            SizedBox(height: selected ? 2 : 6),
            if (selected)
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}
