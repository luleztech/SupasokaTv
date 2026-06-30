import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/screens/home_screen.dart';
import 'package:supasoka/screens/payment_screen.dart';
import 'package:supasoka/screens/profile_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/theme/brand_palette.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cs = context.read<ContentStore>();
      if (cs.ready) {
        unawaited(cs.pollConfigMeta());
        unawaited(SubscriptionStore.syncPremiumFromBackend());
      }
    });
    _configPoll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final cs = context.read<ContentStore>();
      if (cs.ready) {
        unawaited(cs.pollConfigMeta());
        unawaited(SubscriptionStore.syncPremiumFromBackend());
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
    final refreshing = context.watch<ContentStore>().refreshing;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          backgroundColor: BrandPalette.bgDeep,
          extendBody: true,
          body: Column(
            children: [
              if (refreshing)
                const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: BrandPalette.bgMid,
                  color: BrandPalette.accent,
                ),
              Expanded(
                child: IndexedStack(
                  index: nav.currentTab,
                  children: const [
                    HomeScreen(key: ValueKey('home_tab')),
                    PaymentScreen(key: ValueKey('unlock_tab')),
                    ProfileScreen(key: ValueKey('profile_tab')),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 14),
            child: SizedBox(
              height: 56,
              child: Center(
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: BrandPalette.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        _FloatingNavItem(
                          selected: nav.currentTab == AppTab.home,
                          onTap: () => _onTabTap(context, AppTab.home),
                          label: 'Nyumbani',
                          icon: Ionicons.home_outline,
                          activeIcon: Ionicons.home,
                        ),
                        const SizedBox(width: 4),
                        _FloatingNavItem(
                          selected: nav.currentTab == AppTab.unlock,
                          onTap: () => _onTabTap(context, AppTab.unlock),
                          label: 'Fungua',
                          icon: Ionicons.key_outline,
                          activeIcon: Ionicons.key,
                        ),
                        const SizedBox(width: 4),
                        _FloatingNavItem(
                          selected: nav.currentTab == AppTab.profile,
                          onTap: () => _onTabTap(context, AppTab.profile),
                          label: 'Akaunti',
                          icon: Ionicons.person_outline,
                          activeIcon: Ionicons.person,
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
              color: BrandPalette.bgDeep.withValues(alpha: 0.97),
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

  void _onTabTap(BuildContext context, int i) {
    final changed = context.read<AppNav>().setTab(i);
    if (!changed) return;
    final store = context.read<ContentStore>();
    if (i == AppTab.unlock) {
      unawaited(store.refresh());
    } else {
      unawaited(store.pollConfigMeta());
    }
  }
}

class _FloatingNavItem extends StatelessWidget {
  const _FloatingNavItem({
    required this.selected,
    required this.onTap,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final bool selected;
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final IconData activeIcon;

  static const _inactiveIcon = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        splashColor: BrandPalette.bgMid.withValues(alpha: 0.08),
        highlightColor: BrandPalette.bgMid.withValues(alpha: 0.04),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 40),
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 14 : 10,
            vertical: selected ? 7 : 5,
          ),
          decoration: BoxDecoration(
            color: selected ? BrandPalette.bgMid : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? activeIcon : icon,
                size: 20,
                color: selected ? BrandPalette.white : _inactiveIcon,
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  style: inter(12, weight: FontWeight.w700).copyWith(
                    color: BrandPalette.white,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
