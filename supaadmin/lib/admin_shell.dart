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
  bool _navOpen = false;

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

  void _toggleNav() => setState(() => _navOpen = !_navOpen);

  void _selectNav(int i) {
    final wide = MediaQuery.sizeOf(context).width >= _kWideBreakpoint;
    setState(() {
      _prevIndex = _index;
      _index = i;
      if (!wide) _navOpen = false;
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
      extended: wide,
      showLabels: showLabels,
      selectedIndex: _index,
      onDestinationSelected: _selectNav,
      destinations: _destinations,
      onCollapse: wide ? _toggleNav : null,
    );

    final contentStack = Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: !_navOpen ? 52 : 0,
          ),
          child: page,
        ),
        if (!_navOpen)
          Positioned(
            top: 4,
            left: 8,
            child: SafeArea(
              bottom: false,
              child: _NavToggleButton(
                isOpen: wide && _navOpen,
                onPressed: _toggleNav,
              ),
            ),
          ),
      ],
    );

    return Scaffold(
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
                    ClipRect(
                      child: AnimatedContainer(
                        duration: _kNavAnim,
                        curve: _kNavCurve,
                        alignment: Alignment.centerLeft,
                        width: _navOpen ? 212.0 : 0,
                        child: SizedBox(width: 212, child: rail),
                      ),
                    ),
                    Expanded(child: contentStack),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    contentStack,
                    AnimatedOpacity(
                      opacity: _navOpen ? 1 : 0,
                      duration: _kNavAnim,
                      curve: _kNavCurve,
                      child: IgnorePointer(
                        ignoring: !_navOpen,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _toggleNav,
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.52),
                          ),
                        ),
                      ),
                    ),
                    AnimatedSlide(
                      duration: _kNavAnim,
                      curve: _kNavCurve,
                      offset: _navOpen ? Offset.zero : const Offset(-1, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Material(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: 78,
                            height: double.infinity,
                            child: rail,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Floating hamburger / menu-open control with smooth scale on press.
class _NavToggleButton extends StatelessWidget {
  const _NavToggleButton({
    required this.isOpen,
    required this.onPressed,
  });

  final bool isOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xFF141824).withValues(alpha: 0.92),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) {
              return ScaleTransition(scale: anim, child: child);
            },
            child: Icon(
              isOpen ? Icons.menu_open_rounded : Icons.menu_rounded,
              key: ValueKey(isOpen),
              color: cs.primary,
              size: 26,
            ),
          ),
        ),
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
    this.onCollapse,
  });

  final bool extended;
  final bool showLabels;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_Nav> destinations;
  final VoidCallback? onCollapse;

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
                    if (onCollapse != null) ...[
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Hide menu',
                        onPressed: onCollapse,
                        icon: Icon(
                          Icons.menu_open_rounded,
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
