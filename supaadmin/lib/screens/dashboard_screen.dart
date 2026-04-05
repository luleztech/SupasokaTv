import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/admin_store.dart';
import '../widgets/admin_page_header.dart';
import '../widgets/stagger_entrance.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final c = store.config;
    final cs = Theme.of(context).colorScheme;

    final stats = [
      _Stat('Channels', '${c.channels.length}', Icons.tv_rounded, const Color(0xFF8b5cf6)),
      _Stat('Carousel', '${c.carousel.length}', Icons.view_carousel_rounded, const Color(0xFF06b6d4)),
      _Stat('Premium', '${c.premiumPackages.length}', Icons.card_membership_rounded, const Color(0xFFf97316)),
      _Stat('Malipo', '${c.malipoPlans.length}', Icons.payments_rounded, const Color(0xFF22c55e)),
      _Stat('Live', '${c.liveMatches.length}', Icons.live_tv_rounded, const Color(0xFFec4899)),
      _Stat('Pushes', '${c.notificationLog.length}', Icons.notifications_active_rounded, const Color(0xFFeab308)),
    ];

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(
            child: StaggerEntrance(
              index: 0,
              child: AdminPageHeader(
                title: 'Overview',
                subtitle: 'Tazama maendeleo ya App hapa',
                icon: Icons.dashboard_customize_rounded,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: StaggerEntrance(
              index: 1,
              slide: 28,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primary.withValues(alpha: 0.22),
                      cs.tertiary.withValues(alpha: 0.12),
                      const Color(0xFF161a24).withValues(alpha: 0.9),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.bolt_rounded, color: cs.primary, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Fungua menu upande wa kushoto ili kuona mipangilio zaidi',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.35,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final cross = w >= 520 ? 3 : 2;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: cross,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: cross == 3 ? 1.15 : 1.05,
                  children: [
                    for (var i = 0; i < stats.length; i++)
                      StaggerEntrance(
                        index: i + 2,
                        child: _StatTile(stat: stats[i]),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat {
  const _Stat(this.title, this.value, this.icon, this.accent);
  final String title;
  final String value;
  final IconData icon;
  final Color accent;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(20),
        splashColor: stat.accent.withValues(alpha: 0.12),
        highlightColor: stat.accent.withValues(alpha: 0.06),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF161a24),
                const Color(0xFF12151c),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: stat.accent.withValues(alpha: 0.18),
                ),
                child: Icon(stat.icon, color: stat.accent, size: 22),
              ),
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutBack,
                builder: (context, t, _) {
                  return Transform.scale(
                    scale: 0.85 + 0.15 * t,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      stat.value,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                stat.title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
