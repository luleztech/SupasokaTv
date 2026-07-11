import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_config.dart';
import '../store/admin_store.dart';
import '../widgets/admin_page_header.dart';
import '../widgets/channel_editor_sheet.dart';
import '../widgets/stagger_entrance.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  final _searchFocus = FocusNode();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool _matchesSearch(ChannelDto ch, String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return true;
    if (ch.name.toLowerCase().contains(s)) return true;
    if ('${ch.id}'.contains(s)) return true;
    if (ch.cat.toLowerCase().contains(s)) return true;
    if (channelCategoryLabel(ch.cat).toLowerCase().contains(s)) return true;
    if (ch.url.toLowerCase().contains(s)) return true;
    if (ch.drm.toLowerCase().contains(s)) return true;
    if (ch.viewers.toLowerCase().contains(s)) return true;
    if (!ch.free && (s.contains('premium') || s == 'paid')) return true;
    if (ch.free && s.contains('free')) return true;
    if (!ch.enabled && (s.contains('disabled') || s.contains('inactive') || s.contains('off'))) {
      return true;
    }
    if (ch.enabled && (s.contains('active') || s.contains('enabled'))) return true;
    return false;
  }

  List<ChannelDto> _filtered(List<ChannelDto> all) =>
      all.where((ch) => _matchesSearch(ch, _searchQuery)).toList();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final all = store.config.channels;
    final searching = _searchQuery.trim().isNotEmpty;
    final list = searching ? _filtered(all) : all;
    final cs = Theme.of(context).colorScheme;

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
                AdminPageHeader(
                  title: 'Channels',
                  subtitle: searching
                      ? '${list.length} of ${all.length} channels'
                      : 'Buruta kupanga · Premium · Active — gusa kuhariri.',
                  icon: Icons.tv_rounded,
                  actions: [
                    FilledButton.icon(
                      onPressed: () => showChannelEditorSheet(context, store, null),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search name, ID, category, URL, DRM…',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                    prefixIcon: Icon(Icons.search_rounded, color: cs.primary.withValues(alpha: 0.9)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear',
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
          const SizedBox(height: 16),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      searching ? 'No channels match your search.' : 'No channels yet. Tap Add.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                      textAlign: TextAlign.center,
                    ),
                  )
                : searching
                    ? ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final ch = list[i];
                          return Padding(
                            key: ValueKey('ch_search_${ch.id}'),
                            padding: const EdgeInsets.only(bottom: 10),
                            child: StaggerEntrance(
                              index: i,
                              child: _ChannelCard(
                                index: i,
                                channel: ch,
                                reorderable: false,
                                onEdit: () => showChannelEditorSheet(context, store, ch),
                                onDelete: () => _confirmDelete(context, store, ch),
                                onActiveChanged: (v) => store.upsertChannel(ch.copyWith(enabled: v)),
                              ),
                            ),
                          );
                        },
                      )
                    : ReorderableListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: list.length,
                        onReorder: store.reorderChannels,
                        proxyDecorator: (child, index, animation) {
                          return AnimatedBuilder(
                            animation: animation,
                            builder: (context, c) {
                              final t = Curves.easeOut.transform(animation.value);
                              return Transform.scale(
                                scale: 1.0 + 0.02 * t,
                                child: Material(
                                  elevation: 6 * t,
                                  borderRadius: BorderRadius.circular(18),
                                  color: Colors.transparent,
                                  child: c,
                                ),
                              );
                            },
                            child: child,
                          );
                        },
                        itemBuilder: (context, i) {
                          final ch = list[i];
                          return Padding(
                            key: ValueKey('ch_${ch.id}_$i'),
                            padding: const EdgeInsets.only(bottom: 10),
                            child: StaggerEntrance(
                              index: i,
                              child: _ChannelCard(
                                index: i,
                                channel: ch,
                                reorderable: true,
                                onEdit: () => showChannelEditorSheet(context, store, ch),
                                onDelete: () => _confirmDelete(context, store, ch),
                                onActiveChanged: (v) => store.upsertChannel(ch.copyWith(enabled: v)),
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

  Future<void> _confirmDelete(BuildContext context, AdminStore store, ChannelDto ch) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete channel?'),
        content: Text('Remove "${ch.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await store.deleteChannel(ch.id);
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.index,
    required this.channel,
    required this.reorderable,
    required this.onEdit,
    required this.onDelete,
    required this.onActiveChanged,
  });

  final int index;
  final ChannelDto channel;
  final bool reorderable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = channel.enabled;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: enabled ? Colors.white.withValues(alpha: 0.08) : cs.error.withValues(alpha: 0.35),
            ),
            gradient: LinearGradient(
              colors: enabled
                  ? const [Color(0xFF161a24), Color(0xFF12151c)]
                  : [Color(0xFF14161c), Color(0xFF0e1015)],
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reorderable)
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6, right: 4),
                    child: Icon(Icons.drag_indicator_rounded, color: Colors.white.withValues(alpha: 0.35)),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4),
                  child: Icon(Icons.tv_rounded, size: 22, color: Colors.white.withValues(alpha: 0.25)),
                ),
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Image.network(
                        channel.img,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => ColoredBox(
                          color: cs.surfaceContainerHighest,
                          child: Icon(Icons.image_not_supported_outlined, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                  if (!enabled)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.black54,
                        ),
                        child: const Icon(Icons.block_rounded, color: Colors.white54, size: 24),
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
                      channel.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: enabled ? null : Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Chip(
                          label: Text('#${channel.id}', style: const TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        Chip(
                          label: Text(
                            channelCategoryLabel(channel.cat),
                            style: const TextStyle(fontSize: 10),
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        Chip(
                          label: Text(
                            !channel.free ? 'Premium' : 'Free',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: !channel.free ? const Color(0x33FFD700) : cs.primary.withValues(alpha: 0.15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            channel.viewers,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                          ),
                        ),
                        Text('Active', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
                        const SizedBox(width: 6),
                        Switch.adaptive(
                          value: channel.enabled,
                          onChanged: onActiveChanged,
                        ),
                      ],
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
