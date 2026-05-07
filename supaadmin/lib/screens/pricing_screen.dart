import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_config.dart';
import '../store/admin_store.dart';
import '../widgets/admin_page_header.dart';
import '../widgets/malipo_plan_sheet.dart';
import '../widgets/stagger_entrance.dart';

class PricingScreen extends StatelessWidget {
  const PricingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final list = store.config.malipoPlans;

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
                  title: 'Malipo',
                  icon: Icons.payments_rounded,
                  actions: [
                    FilledButton.icon(
                      onPressed: () => showMalipoPlanSheet(context, store, null),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Ongeza mpango'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Mipango ${list.length} · Bei, kipindi na beji — gusa kuhariri',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: list.isEmpty
                    ? _MalipoEmptyCallout(
                        onAdd: () => showMalipoPlanSheet(context, store, null),
                      )
                    : narrow
                        ? ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (context, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final m = list[i];
                          return _MalipoPlanCard(
                            m: m,
                            onEdit: () => showMalipoPlanSheet(context, store, m),
                            onDelete: () => _confirmDeleteMalipo(context, store, m),
                          );
                        },
                      )
                    : Scrollbar(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: DataTable(
                              showCheckboxColumn: false,
                              headingRowColor: WidgetStatePropertyAll(
                                Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                              ),
                              columns: const [
                                DataColumn(label: Text('Kitambulisho')),
                                DataColumn(label: Text('Jina')),
                                DataColumn(label: Text('Kipindi')),
                                DataColumn(label: Text('Beji')),
                                DataColumn(label: Text('Kiasi')),
                                DataColumn(label: Text('')),
                              ],
                              rows: [
                                for (final m in list)
                                  DataRow(
                                    cells: _malipoDataCells(context, store, m),
                                  ),
                              ],
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

  List<DataCell> _malipoDataCells(BuildContext context, AdminStore store, MalipoPlanDto m) {
    void edit() => showMalipoPlanSheet(context, store, m);

    return [
      DataCell(Text(m.id), onTap: edit),
      DataCell(
        Text(m.label.trim().isEmpty ? '—' : m.label),
        onTap: edit,
      ),
      DataCell(Text(m.period), onTap: edit),
      DataCell(
        Text(m.badge.isEmpty ? '—' : m.badge),
        onTap: edit,
      ),
      DataCell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_outlined, size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(m.amount, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        onTap: edit,
      ),
      DataCell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Hariri mpango',
              icon: const Icon(Icons.edit_rounded, size: 22),
              onPressed: () => showMalipoPlanSheet(context, store, m),
            ),
            IconButton(
              tooltip: 'Futa',
              icon: Icon(Icons.delete_outline_rounded, size: 22, color: Theme.of(context).colorScheme.error),
              onPressed: () => _confirmDeleteMalipo(context, store, m),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _confirmDeleteMalipo(BuildContext context, AdminStore store, MalipoPlanDto m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Futa mpango?'),
        content: Text(
          'Una uhakika unataka kuondoa mpango wa "${m.label.trim().isNotEmpty ? m.label : m.period}"?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ghairi')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Futa')),
        ],
      ),
    );
    if (ok == true) await store.deleteMalipo(m.id);
  }
}

class _MalipoEmptyCallout extends StatelessWidget {
  const _MalipoEmptyCallout({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            gradient: LinearGradient(
              colors: [
                cs.surfaceContainerHighest.withValues(alpha: 0.4),
                cs.surface.withValues(alpha: 0.15),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 30, 26, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.price_change_outlined, size: 48, color: cs.primary.withValues(alpha: 0.95)),
                const SizedBox(height: 18),
                Text(
                  'Hakuna mipango ya malipo',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Ongeza mpango wa kwanza (bei TZS, jina na kipindi). Baada ya uhifadhi, uhakikishe seva imesasishwa ili bei ionekane kwenye programu ya mtazamaji.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.52),
                    height: 1.45,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Ongeza mpango wa kwanza'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MalipoPlanCard extends StatelessWidget {
  const _MalipoPlanCard({
    required this.m,
    required this.onEdit,
    required this.onDelete,
  });

  final MalipoPlanDto m;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = m.label.trim().isNotEmpty ? m.label : m.period;
    final showPeriodSubtitle = m.label.trim().isNotEmpty && m.label.trim() != m.period.trim();

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
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: cs.tertiary.withValues(alpha: 0.2),
                          ),
                          child: Text(
                            m.id,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (m.badge.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: cs.primary.withValues(alpha: 0.22),
                              border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              m.badge,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    if (showPeriodSubtitle) ...[
                      const SizedBox(height: 4),
                      Text(
                        m.period,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.52),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      m.amount,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Gusa kuhariri bei, jina, kipindi na beji',
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.35)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Hariri',
                onPressed: onEdit,
                icon: Icon(Icons.edit_rounded, color: cs.primary),
              ),
              IconButton(
                tooltip: 'Futa',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded, color: cs.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
