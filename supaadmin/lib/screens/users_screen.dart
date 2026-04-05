import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_config.dart';
import '../store/admin_store.dart';
import '../widgets/admin_page_header.dart';
import '../widgets/stagger_entrance.dart';
import '../widgets/user_manage_sheet.dart';

enum _UserFilter { all, premium, expired, free }

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  _UserFilter _filter = _UserFilter.all;

  bool _matches(UserDto u, _UserFilter f) {
    switch (f) {
      case _UserFilter.all:
        return true;
      case _UserFilter.premium:
        return UserDto.isPremiumNow(u.premiumUntilMs);
      case _UserFilter.expired:
        return UserDto.isExpired(u.premiumUntilMs);
      case _UserFilter.free:
        return u.premiumUntilMs == null;
    }
  }

  List<UserDto> _filtered(List<UserDto> all) => all.where((u) => _matches(u, _filter)).toList();

  Future<void> _addUser(BuildContext context, AdminStore store) async {
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    bool? ok;
    String id = '';
    String name = '';
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mtumiaji mpya'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kitambulisho (ID)',
                  hintText: 'device / user id',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Jina la mtumiaji',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ghairi')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ongeza')),
          ],
        ),
      );
      if (ok == true) {
        id = idCtrl.text.trim();
        name = nameCtrl.text.trim();
      }
    } finally {
      idCtrl.dispose();
      nameCtrl.dispose();
    }
    if (ok != true || !context.mounted) return;
    if (id.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jaza ID na jina')),
      );
      return;
    }
    if (store.config.users.any((u) => u.id == id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID hii tayari ipo')),
      );
      return;
    }
    await store.upsertUser(UserDto(id: id, username: name, premiumUntilMs: null, note: ''));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mtumiaji ameongezwa')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, AdminStore store, UserDto u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Futa mtumiaji?'),
        content: Text('"${u.username}" — hatua hii haiwezi kutenduliwa kwenye simu ya mtumiaji bila sync.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ghairi')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Futa')),
        ],
      ),
    );
    if (ok == true) await store.deleteUser(u.id);
  }

  String _statusShort(UserDto u) {
    if (UserDto.isPremiumNow(u.premiumUntilMs)) return 'Premium';
    if (u.premiumUntilMs != null) return 'Imeisha';
    return 'Bure';
  }

  Color _statusColor(BuildContext context, UserDto u) {
    final cs = Theme.of(context).colorScheme;
    if (UserDto.isPremiumNow(u.premiumUntilMs)) return const Color(0xFFFFD700);
    if (u.premiumUntilMs != null) return cs.error;
    return cs.primary;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final all = store.config.users;
    final list = _filtered(all);
    final cs = Theme.of(context).colorScheme;

    int count(_UserFilter f) => all.where((u) => _matches(u, f)).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StaggerEntrance(
            index: 0,
            child: AdminPageHeader(
              title: 'Users',
              subtitle: 'Premium · walioisha · bure — Dhibiti muda wa kila mtumiaji.',
              icon: Icons.group_rounded,
              actions: [
                FilledButton.icon(
                  onPressed: () => _addUser(context, store),
                  icon: const Icon(Icons.person_add_rounded),
                  label: const Text('Ongeza'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'Wote (${count(_UserFilter.all)})',
                  selected: _filter == _UserFilter.all,
                  onSelected: () => setState(() => _filter = _UserFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Premium (${count(_UserFilter.premium)})',
                  selected: _filter == _UserFilter.premium,
                  onSelected: () => setState(() => _filter = _UserFilter.premium),
                  accent: const Color(0xFFFFD700),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Walioisha (${count(_UserFilter.expired)})',
                  selected: _filter == _UserFilter.expired,
                  onSelected: () => setState(() => _filter = _UserFilter.expired),
                  accent: cs.error,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Bure (${count(_UserFilter.free)})',
                  selected: _filter == _UserFilter.free,
                  onSelected: () => setState(() => _filter = _UserFilter.free),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      'Hakuna watumiaji kwenye kichujio hiki.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final u = list[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: StaggerEntrance(
                          index: i,
                          child: _UserCard(
                            user: u,
                            statusLabel: _statusShort(u),
                            statusColor: _statusColor(context, u),
                            onManage: () => showUserManageSheet(context, u),
                            onDelete: () => _confirmDelete(context, store, u),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = accent ?? cs.primary;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: c.withValues(alpha: 0.28),
      checkmarkColor: c,
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
        color: selected ? Colors.white : Colors.white70,
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.statusLabel,
    required this.statusColor,
    required this.onManage,
    required this.onDelete,
  });

  final UserDto user;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback onManage;
  final VoidCallback onDelete;

  String _expiryLine(UserDto u) {
    if (u.premiumUntilMs == null) return 'Premium: —';
    final d = DateTime.fromMillisecondsSinceEpoch(u.premiumUntilMs!);
    final two = (int n) => n.toString().padLeft(2, '0');
    return 'Mwisho: ${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onManage,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            gradient: const LinearGradient(
              colors: [Color(0xFF161a24), Color(0xFF12151c)],
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: cs.primary.withValues(alpha: 0.2),
                child: Text(
                  user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.username,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.id,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Chip(
                          label: Text(
                            statusLabel,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: statusColor.withValues(alpha: 0.2),
                        ),
                        Chip(
                          label: Text(
                            _expiryLine(user),
                            style: const TextStyle(fontSize: 10),
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                    if (user.note.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        user.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonal(
                    onPressed: onManage,
                    child: const Text('Dhibiti'),
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline_rounded, size: 20, color: cs.error),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
