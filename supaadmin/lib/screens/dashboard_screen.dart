import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/admin_store.dart';
import '../widgets/admin_page_header.dart';
import '../widgets/stagger_entrance.dart';

String _formatTzs(int amountTzs) {
  if (amountTzs < 1000) return 'TZS $amountTzs';
  if (amountTzs < 1000000) {
    final k = (amountTzs / 1000).toStringAsFixed(1);
    return 'TZS ${k}K';
  }
  final m = (amountTzs / 1000000).toStringAsFixed(1);
  return 'TZS ${m}M';
}

String _formatTzsFull(int amountTzs) {
  final s = amountTzs.toString();
  final buf = StringBuffer('TZS ');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _revenueDayLabel(String dayIso, {required String todayDay}) {
  if (dayIso == todayDay) return 'Leo';
  final parts = dayIso.split('-');
  if (parts.length == 3 && todayDay.split('-').length == 3) {
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    final ty = int.tryParse(todayDay.split('-')[0]);
    final tm = int.tryParse(todayDay.split('-')[1]);
    final td = int.tryParse(todayDay.split('-')[2]);
    if (y != null && m != null && d != null && ty != null && tm != null && td != null) {
      final day = DateTime(y, m, d);
      final today = DateTime(ty, tm, td);
      if (today.difference(day).inDays == 1) return 'Jana';
    }
  }
  final parsed = DateTime.tryParse(dayIso);
  if (parsed == null) return dayIso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final c = store.config;
    final cs = Theme.of(context).colorScheme;
    final syncing = store.syncingToServer;

    final stats = [
      _Stat('Channels', '${c.channels.length}', Icons.tv_rounded, const Color(0xFF8b5cf6)),
      _Stat('Carousel', '${c.carousel.length}', Icons.view_carousel_rounded, const Color(0xFF06b6d4)),
      _Stat('Premium', '${c.premiumPackages.length}', Icons.card_membership_rounded, const Color(0xFFf97316)),
      _Stat('Malipo', '${c.malipoPlans.length}', Icons.payments_rounded, const Color(0xFF22c55e)),
      _Stat('Live', '${c.liveMatches.length}', Icons.live_tv_rounded, const Color(0xFFec4899)),
      _Stat('Pushes', '${c.notificationLog.length}', Icons.notifications_active_rounded, const Color(0xFFeab308)),
    ];
    final payment = store.paymentHealthSummary;
    final totalPayments = payment['total'] ?? 0;
    final pendingPayments = payment['pending'] ?? 0;
    final completedPayments = payment['completed'] ?? 0;
    final activatedPayments = payment['activated'] ?? 0;
    final totalCollectionsTzs = payment['totalCollectionsTzs'] ?? 0;
    final todayCollectionsTzs = payment['todayCollectionsTzs'] ?? 0;
    final todayCompleted = payment['todayCompleted'] ?? 0;
    final dailyRevenue = store.paymentDailyRevenue;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(
            child: StaggerEntrance(
              index: 0,
              child: Row(
                children: [
                  Expanded(
                    child: AdminPageHeader(
                      title: 'Overview',
                      subtitle: 'Tazama maendeleo ya App hapa',
                      icon: Icons.dashboard_customize_rounded,
                    ),
                  ),
                  if (store.hasAdminSession)
                    FilledButton.icon(
                      onPressed: syncing ? null : store.syncToServer,
                      icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                      label: syncing ? const Text('Syncing...') : const Text('Sync'),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (store.lastSyncError != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            sliver: SliverToBoxAdapter(
              child: StaggerEntrance(
                index: 1,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.1),
                    border: Border.all(color: cs.error.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    store.lastSyncError!,
                    style: TextStyle(color: cs.error, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: StaggerEntrance(
              index: 2,
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
                        index: i + 3,
                        child: _StatTile(stat: stats[i]),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(
            child: StaggerEntrance(
              index: 9,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF14532d).withValues(alpha: 0.55),
                      const Color(0xFF12151c),
                    ],
                  ),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.green.withValues(alpha: 0.18),
                          ),
                          child: Icon(Icons.payments_rounded, color: Colors.green.shade300, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Revenue leo',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              Text(
                                'Malipo yaliyofanikiwa tu · EAT',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh revenue',
                          onPressed: store.loadingPaymentHealth ? null : store.refreshPaymentHealth,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      store.loadingPaymentHealth && todayCollectionsTzs == 0 && todayCompleted == 0
                          ? '—'
                          : _formatTzsFull(todayCollectionsTzs),
                      style: TextStyle(
                        color: Colors.green.shade300,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      todayCompleted == 1
                          ? '1 malipo lililofanikiwa leo'
                          : '$todayCompleted malipo yaliyofanikiwa leo',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (dailyRevenue.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Siku za hivi karibuni',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...dailyRevenue.take(7).map((row) {
                        final day = row['day'] ?? '';
                        final count = int.tryParse(row['count'] ?? '0') ?? 0;
                        final total = int.tryParse(row['totalTzs'] ?? '0') ?? 0;
                        final isToday = day == store.revenueTodayDay;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _revenueDayLabel(day, todayDay: store.revenueTodayDay),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                                    color: Colors.white.withValues(alpha: isToday ? 0.95 : 0.72),
                                  ),
                                ),
                              ),
                              Text(
                                count == 1 ? '1 txn' : '$count txn',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white.withValues(alpha: 0.45),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _formatTzs(total),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.green.shade300.withValues(alpha: isToday ? 1 : 0.85),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ] else if (!store.loadingPaymentHealth)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Hakuna malipo yaliyofanikiwa bado.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          sliver: SliverToBoxAdapter(
            child: StaggerEntrance(
              index: 10,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFF12151c),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.monitor_heart_rounded, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Payment Health',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh payment health',
                          onPressed: store.loadingPaymentHealth ? null : store.refreshPaymentHealth,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    Text(
                      'Total $totalPayments  ·  Pending $pendingPayments  ·  Completed $completedPayments  ·  Activated $activatedPayments',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.green.withValues(alpha: 0.15),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.trending_up_rounded, color: Colors.green.shade300, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Total Collections: ${_formatTzs(totalCollectionsTzs)}',
                              style: TextStyle(
                                color: Colors.green.shade300,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (store.paymentHealthRecent.isEmpty)
                      Text(
                        store.loadingPaymentHealth ? 'Loading payment events...' : 'No payment events yet.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                      )
                    else
                      ...store.paymentHealthRecent.take(5).map(
                            (r) {
                              final amountTzs = int.tryParse(r['amountTzs'] ?? '0') ?? 0;
                              final amountDisplay = amountTzs > 0 ? ' · ${_formatTzs(amountTzs)}' : '';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '${r['status'] ?? 'PENDING'} · ${r['planId'] ?? '-'} · ${r['publicId'] ?? '-'}$amountDisplay',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.82),
                                  ),
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
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
