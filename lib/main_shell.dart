import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/screens/channels_screen.dart';
import 'package:supasoka/screens/home_screen.dart';
import 'package:supasoka/screens/live_screen.dart';
import 'package:supasoka/screens/payment_screen.dart';
import 'package:supasoka/screens/profile_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/widgets/internet_required_card.dart';

/// Fast `/config-meta` poll + full fetch only when the server sync cursor changes (admin updates).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  Timer? _configPoll;

  @override
  void initState() {
    super.initState();
    // Catch admin sync (pricing, channels) sooner than waiting for the first interval tick.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cs = context.read<ContentStore>();
      if (cs.ready) unawaited(cs.pollConfigMeta());
    });
    _configPoll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final cs = context.read<ContentStore>();
      if (cs.ready) {
        unawaited(cs.pollConfigMeta());
      }
    });
  }

  @override
  void dispose() {
    _configPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppNav>();
    final t = context.watch<ThemeController>().colors;
    final refreshing = context.watch<ContentStore>().refreshing;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
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
                    LiveScreen(),
                    ChannelsScreen(),
                    PaymentScreen(),
                    ProfileScreen(),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF0B0D12).withValues(alpha: 0.92),
                        const Color(0xFF131722).withValues(alpha: 0.88),
                      ],
                    ),
                    border: Border.all(color: t.border.withValues(alpha: 0.55)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.40),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Row(
                    children: [
                      _TabButton(
                        i: 0,
                        label: 'Home',
                        outline: Ionicons.home_outline,
                        solid: Ionicons.home,
                        selected: nav.currentTab == 0,
                      ),
                      _TabButton(
                        i: 1,
                        label: 'Live',
                        outline: Ionicons.radio_outline,
                        solid: Ionicons.radio,
                        selected: nav.currentTab == 1,
                      ),
                      _TabButton(
                        i: 2,
                        label: 'Channels',
                        outline: Ionicons.tv_outline,
                        solid: Ionicons.tv,
                        selected: nav.currentTab == 2,
                      ),
                      _TabButton(
                        i: 3,
                        label: 'Fungua zote',
                        outline: Ionicons.key_outline,
                        solid: Ionicons.key,
                        selected: nav.currentTab == 3,
                      ),
                      _TabButton(
                        i: 4,
                        label: 'Mtumiaji',
                        outline: Ionicons.person_outline,
                        solid: Ionicons.person,
                        selected: nav.currentTab == 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (context.watch<ContentStore>().connectionBlocked)
          Positioned.fill(
            child: Material(
              color: const Color(0xFF06060A).withValues(alpha: 0.97),
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: InternetRequiredCard(
                      busy: refreshing,
                      onRetry: () {
                        final cs = context.read<ContentStore>();
                        unawaited(cs.refresh());
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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
    final active = t.accent;
    const activeIcon = Colors.white;
    final idle = const Color(0xFF71717a);
    final activeText = Color.lerp(const Color(0xFFD9FEE7), Colors.white, 0.35)!;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          final changed = context.read<AppNav>().setTab(i);
          if (changed) {
            final store = context.read<ContentStore>();
            // Unlock / pricing: always pull latest so admin price edits show immediately.
            if (i == 3) {
              unawaited(store.refresh());
            } else {
              unawaited(store.pollConfigMeta());
            }
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      active.withValues(alpha: 0.22),
                      active.withValues(alpha: 0.10),
                    ],
                  )
                : null,
            border: Border.all(
              color: selected
                  ? active.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: active.withValues(alpha: 0.26),
                      blurRadius: 16,
                      spreadRadius: -5,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: AnimatedScale(
            scale: selected ? 1.04 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 21, color: selected ? activeIcon : idle),
                const SizedBox(height: 4),
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: label.length > 10 ? 8.5 : 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.35,
                    height: 1.1,
                    color: selected ? activeText : idle,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: selected ? 16 : 0,
                  height: 2.2,
                  decoration: BoxDecoration(
                    color: active,
                    borderRadius: BorderRadius.circular(99),
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
