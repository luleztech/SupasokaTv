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
  final _searchFocus = FocusNode();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _fmtJoinedMs(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

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

  bool _matchesSearch(UserDto u, String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return true;
    return u.id.toLowerCase().contains(s) ||
        u.username.toLowerCase().contains(s) ||
        u.note.toLowerCase().contains(s);
  }

  List<UserDto> _filtered(List<UserDto> all) =>
      all.where((u) => _matches(u, _filter)).where((u) => _matchesSearch(u, _searchQuery)).toList();

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
    final emptyMsg = all.isEmpty
        ? 'Hakuna watumiaji kwenye kichujio hiki.'
        : (_searchQuery.trim().isNotEmpty
            ? 'Hakuna matokeo ya utafutaji.'
            : 'Hakuna watumiaji kwenye kichujio hiki.');

    int count(_UserFilter f) => all.where((u) => _matches(u, f)).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StaggerEntrance(
            index: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AdminPageHeader(
                  title: 'Users',
                  subtitle: 'Premium · walioisha · bure — Dhibiti muda wa kila mtumiaji.',
                  icon: Icons.group_rounded,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Tafuta kwa ID, jina, maelezo…',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                    prefixIcon: Icon(Icons.search_rounded, color: cs.primary.withValues(alpha: 0.9)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            tooltip: 'Futa',
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.45)),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.65), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                  ),
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
            child: RefreshIndicator(
              color: cs.primary,
              onRefresh: () => store.refreshUsersFromServer(),
              child: list.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 280,
                          child: Center(
                            child: Text(
                              emptyMsg,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
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
                              joinedLabel: u.createdAtMs != null ? _fmtJoinedMs(u.createdAtMs!) : null,
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
    this.joinedLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.onManage,
    required this.onDelete,
  });

  final UserDto user;
  final String? joinedLabel;
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
                    if (joinedLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Alijiunga: $joinedLabel',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                      ),
                    ],
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
