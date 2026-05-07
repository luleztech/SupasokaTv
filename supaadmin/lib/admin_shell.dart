import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import 'screens/carousel_screen.dart';
import 'screens/channels_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/live_matches_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/pricing_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/users_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  int _prevIndex = 0;
  bool _railExtended = true;

  static const _kWideBreakpoint = 960.0;
  static const _kNavAnim = Duration(milliseconds: 320);
  static const _kNavCurve = Curves.easeOutCubic;

  static const _destinations = [
    _Nav(Icons.dashboard_outlined, Icons.dashboard_rounded, 'Overview'),
    _Nav(Icons.tv_outlined, Icons.tv_rounded, 'Channels'),
    _Nav(Icons.view_carousel_outlined, Icons.view_carousel_rounded, 'Carousel'),
    _Nav(Icons.payments_outlined, Icons.payments_rounded, 'Pricing'),
    _Nav(Icons.group_outlined, Icons.group_rounded, 'Users'),
    _Nav(Icons.sports_soccer_outlined, Icons.sports_soccer_rounded, 'Live'),
    _Nav(Icons.notifications_outlined, Icons.notifications_rounded, 'Push'),
    _Nav(Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  void _selectNav(int i) {
    setState(() {
      _prevIndex = _index;
      _index = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= _kWideBreakpoint;
    final showLabels = size.width >= 520;

    final body = [
      const DashboardScreen(),
      const ChannelsScreen(),
      const CarouselScreen(),
      const PricingScreen(),
      const UsersScreen(),
      const LiveMatchesScreen(),
      const NotificationsScreen(),
      const SettingsScreen(),
    ];

    final page = ClipRect(
      child: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 380),
        reverse: _index < _prevIndex,
        transitionBuilder: (child, primary, secondary) {
          return FadeThroughTransition(
            animation: primary,
            secondaryAnimation: secondary,
            fillColor: Colors.transparent,
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey<int>(_index),
          child: body[_index],
        ),
      ),
    );

    final rail = _SideRail(
      extended: wide && _railExtended,
      showLabels: showLabels,
      selectedIndex: _index,
      onDestinationSelected: _selectNav,
      destinations: _destinations,
      onToggleExtended: wide
          ? () => setState(() => _railExtended = !_railExtended)
          : null,
    );

    return Scaffold(
      extendBody: true,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF07080c),
              Color(0xFF0c0f16),
              Color(0xFF10131c),
            ],
          ),
        ),
        child: SafeArea(
          child: wide
              ? Row(
                  children: [
                    AnimatedContainer(
                      duration: _kNavAnim,
                      curve: _kNavCurve,
                      width: _railExtended ? 212 : 86,
                      child: rail,
                    ),
                    Expanded(child: page),
                  ],
                )
              : page,
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : _GlassBottomNav(
              selectedIndex: _index,
              destinations: _destinations,
              onSelected: _selectNav,
            ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.extended,
    required this.showLabels,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.onToggleExtended,
  });

  final bool extended;
  final bool showLabels;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_Nav> destinations;
  final VoidCallback? onToggleExtended;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: extended ? null : 78,
        constraints: BoxConstraints(minWidth: extended ? 212 : 78),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF141824).withValues(alpha: 0.92),
              const Color(0xFF0e1118).withValues(alpha: 0.98),
            ],
          ),
          border: Border(
            right: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(4, 0),
            ),
          ],
        ),
        child: NavigationRail(
          extended: extended,
          minExtendedWidth: 212,
          backgroundColor: Colors.transparent,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          labelType: extended
              ? NavigationRailLabelType.none
              : (showLabels ? NavigationRailLabelType.all : NavigationRailLabelType.none),
          leading: Padding(
            padding: EdgeInsets.fromLTRB(extended ? 12 : 8, 12, extended ? 12 : 8, 20),
            child: Column(
              crossAxisAlignment: extended ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onToggleExtended != null) ...[
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: extended ? 'Compact menu' : 'Expand menu',
                        onPressed: onToggleExtended,
                        icon: Icon(
                          extended ? Icons.first_page_rounded : Icons.last_page_rounded,
                          color: cs.primary.withValues(alpha: 0.9),
                          size: 22,
                        ),
                      ),
                      if (extended) const SizedBox(width: 4),
                    ],
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, t, _) {
                        return Opacity(
                          opacity: t,
                          child: Transform.scale(
                            scale: 0.92 + 0.08 * t,
                            child: Icon(
                              Icons.shield_moon_rounded,
                              color: cs.primary,
                              size: extended ? 34 : 28,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (extended) ...[
                  const SizedBox(height: 10),
                  Text(
                    'SupaAdmin',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                  ),
                  Text(
                    'Supasoka',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.42),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          destinations: [
            for (final d in destinations)
              NavigationRailDestination(
                icon: Icon(d.outlined),
                selectedIcon: Icon(d.filled, color: Colors.white),
                label: Text(d.label),
              ),
          ],
        ),
      ),
    );
  }
}

class _Nav {
  const _Nav(this.outlined, this.filled, this.label);
  final IconData outlined;
  final IconData filled;
  final String label;
}

class _GlassBottomNav extends StatelessWidget {
  const _GlassBottomNav({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_Nav> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF131A2A).withValues(alpha: 0.94),
                const Color(0xFF0E1118).withValues(alpha: 0.94),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            scrollDirection: Axis.horizontal,
            itemCount: destinations.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final d = destinations[i];
              final active = i == selectedIndex;
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(horizontal: active ? 14 : 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: active ? cs.primary.withValues(alpha: 0.23) : Colors.transparent,
                    border: Border.all(
                      color: active ? cs.primary.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(active ? d.filled : d.outlined, size: 20, color: active ? Colors.white : Colors.white70),
                      if (active) ...[
                        const SizedBox(width: 7),
                        Text(
                          d.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
