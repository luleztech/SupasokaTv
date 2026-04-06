import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_config.dart';
import '../store/admin_store.dart';

Future<void> showUserManageSheet(BuildContext context, UserDto user) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12151c),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => UserManageSheet(initial: user),
  );
}

String _fmtDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

class UserManageSheet extends StatefulWidget {
  const UserManageSheet({super.key, required this.initial});

  final UserDto initial;

  @override
  State<UserManageSheet> createState() => _UserManageSheetState();
}

class _UserManageSheetState extends State<UserManageSheet> {
  late TextEditingController _note;
  final _customDays = TextEditingController();

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.initial.note);
  }

  @override
  void dispose() {
    _note.dispose();
    _customDays.dispose();
    super.dispose();
  }

  UserDto _user(AdminStore store) {
    final list = store.config.users;
    for (final u in list) {
      if (u.id == widget.initial.id) return u;
    }
    return widget.initial;
  }

  Future<void> _applyDuration(AdminStore store, Duration d) async {
    await store.addUserPremiumDuration(widget.initial.id, d);
    if (mounted) setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Muda umeongezwa: ${d.inDays} siku')),
      );
    }
  }

  Future<void> _saveNote(AdminStore store) async {
    final u = _user(store);
    await store.upsertUser(u.copyWith(note: _note.text.trim()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maelezo yamehifadhiwa')),
      );
    }
  }

  Future<void> _pickEndDate(AdminStore store) async {
    final u = _user(store);
    final now = DateTime.now();
    final initial = u.premiumUntilMs != null
        ? DateTime.fromMillisecondsSinceEpoch(u.premiumUntilMs!)
        : now.add(const Duration(days: 30));

    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final end = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await store.setUserPremiumUntil(widget.initial.id, end);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mwisho: ${_fmtDateTime(end)}')),
      );
    }
  }

  Future<void> _clearPremium(AdminStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ondoa premium?'),
        content: const Text('Mtumiaji atarudi kwenye kifurushi cha bure.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ghairi')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ondoa')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await store.setUserPremiumUntil(widget.initial.id, null);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Premium imeondolewa')),
      );
    }
  }

  Future<void> _applyCustomDays(AdminStore store) async {
    final raw = _customDays.text.trim();
    final n = int.tryParse(raw);
    if (n == null || n <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weka nambari halali ya siku')),
      );
      return;
    }
    await _applyDuration(store, Duration(days: n));
    _customDays.clear();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final saving = store.syncingToServer;
    final cs = Theme.of(context).colorScheme;
    final u = _user(store);
    final premium = UserDto.isPremiumNow(u.premiumUntilMs);

    String statusLabel;
    Color statusColor;
    if (premium) {
      statusLabel = 'Premium';
      statusColor = const Color(0xFFFFD700);
    } else if (u.premiumUntilMs != null) {
      statusLabel = 'Muda umeisha';
      statusColor = cs.error;
    } else {
      statusLabel = 'Bure';
      statusColor = cs.primary;
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final kb = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    u.username,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(
                  label: Text(statusLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  backgroundColor: statusColor.withValues(alpha: 0.2),
                  side: BorderSide(color: statusColor.withValues(alpha: 0.5)),
                ),
              ],
            ),
            Text(
              'ID: ${u.id}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
            ),
            if (u.premiumUntilMs != null) ...[
              const SizedBox(height: 8),
              Text(
                premium
                    ? 'Premium hadi: ${_fmtDateTime(DateTime.fromMillisecondsSinceEpoch(u.premiumUntilMs!))}'
                    : 'Ilimalizika: ${_fmtDateTime(DateTime.fromMillisecondsSinceEpoch(u.premiumUntilMs!))}',
                style: TextStyle(
                  color: premium ? Colors.white70 : Colors.white54,
                  fontSize: 13,
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Hakuna muda wa premium uliowekwa (bure).',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Ongeza muda',
              style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: saving ? null : () => _applyDuration(store, const Duration(days: 7)),
                  child: const Text('+ Wiki 1'),
                ),
                FilledButton.tonal(
                  onPressed: saving ? null : () => _applyDuration(store, const Duration(days: 30)),
                  child: const Text('+ Mwezi 1'),
                ),
                FilledButton.tonal(
                  onPressed: saving ? null : () => _applyDuration(store, const Duration(days: 365)),
                  child: const Text('+ Mwaka 1'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _customDays,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Siku (maalum)',
                      hintText: 'e.g. 14',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton(
                    onPressed: saving ? null : () => _applyCustomDays(store),
                    child: const Text('Ongeza'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: saving ? null : () => _pickEndDate(store),
              icon: const Icon(Icons.calendar_month_rounded, size: 20),
              label: const Text('Weka tarehe na saa ya mwisho'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: saving || u.premiumUntilMs == null ? null : () => _clearPremium(store),
              icon: Icon(Icons.remove_circle_outline_rounded, size: 20, color: cs.error),
              label: Text('Ondoa premium', style: TextStyle(color: cs.error)),
            ),
            const Divider(height: 32),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Maelezo (admin)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: saving ? null : () => _saveNote(store),
              child: saving
                  ? const SizedBox(
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Hifadhi maelezo'),
            ),
          ],
        ),
      ),
    );
  }
}
