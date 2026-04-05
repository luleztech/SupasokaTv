import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_config.dart';
import '../store/admin_store.dart';
import '../widgets/admin_page_header.dart';
import '../widgets/live_match_sheet.dart';
import '../widgets/stagger_entrance.dart';

ChannelDto? _channelForMatch(AdminStore store, LiveMatchDto m) {
  for (final c in store.config.channels) {
    if (c.id == m.channelId) return c;
  }
  return null;
}

class LiveMatchesScreen extends StatelessWidget {
  const LiveMatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final list = store.config.liveMatches;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggerEntrance(
                index: 0,
                child: AdminPageHeader(
                  title: 'Mechi za moja kwa moja',
                  icon: Icons.sports_soccer_rounded,
                  actions: [
                    FilledButton.icon(
                      onPressed: () => showLiveMatchSheet(context, store, null),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Ongeza mechi'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Chagua chaneli kwa kila mechi · Beji ya LIVE hiari',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: narrow
                    ? ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final m = list[i];
                          return StaggerEntrance(
                            index: i,
                            child: _LiveCard(
                              store: store,
                              match: m,
                              onEdit: () => showLiveMatchSheet(context, store, m),
                              onDelete: () => _confirmDelete(context, store, m),
                            ),
                          );
                        },
                      )
                    : Card(
                        clipBehavior: Clip.antiAlias,
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: DataTable(
                                headingRowColor: WidgetStatePropertyAll(
                                  Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                ),
                                columns: const [
                                  DataColumn(label: Text('ID')),
                                  DataColumn(label: Text('Jina la mechi')),
                                  DataColumn(label: Text('Chaneli')),
                                  DataColumn(label: Text('LIVE')),
                                  DataColumn(label: Text('')),
                                ],
                                rows: [
                                  for (final m in list)
                                    DataRow(
                                      cells: [
                                        DataCell(Text('${m.id}')),
                                        DataCell(
                                          SizedBox(
                                            width: 220,
                                            child: Text(m.title, maxLines: 2),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            _channelForMatch(store, m)?.name ?? '—',
                                          ),
                                        ),
                                        DataCell(Text(m.liveBadge ? 'Ndiyo' : 'Hapana')),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'Hariri',
                                                icon: const Icon(Icons.edit_outlined, size: 20),
                                                onPressed: () => showLiveMatchSheet(context, store, m),
                                              ),
                                              IconButton(
                                                tooltip: 'Futa',
                                                icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error),
                                                onPressed: () => _confirmDelete(context, store, m),
                                              ),
                                            ],
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
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, AdminStore store, LiveMatchDto m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Futa mechi?'),
        content: Text('Una uhakika unataka kuondoa "${m.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ghairi')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Futa')),
        ],
      ),
    );
    if (ok == true) await store.deleteLive(m.id);
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({
    required this.store,
    required this.match,
    required this.onEdit,
    required this.onDelete,
  });

  final AdminStore store;
  final LiveMatchDto match;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ch = _channelForMatch(store, match);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF161a24),
                Color(0xFF12151c),
              ],
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 88,
                      height: 52,
                      child: ch != null
                          ? Image.network(
                              ch.img,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: Icon(Icons.live_tv_rounded, color: cs.onSurfaceVariant),
                              ),
                            )
                          : ColoredBox(
                              color: cs.surfaceContainerHighest,
                              child: Icon(Icons.tv_off_rounded, color: cs.onSurfaceVariant),
                            ),
                    ),
                  ),
                  if (match.liveBadge)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFef4444),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      match.title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.tv_rounded, size: 14, color: cs.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            ch?.name ?? 'Chaneli haipo (ID ${match.channelId})',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gusa kuhariri · Chaneli inatoa URL na picha',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.32), fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_rounded, size: 20)),
              IconButton(onPressed: onDelete, icon: Icon(Icons.delete_outline_rounded, size: 20, color: cs.error)),
            ],
          ),
        ),
      ),
    );
  }
}
