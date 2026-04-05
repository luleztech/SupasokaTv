import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_config.dart';
import '../store/admin_store.dart';

ChannelDto? _channelById(List<ChannelDto> channels, int id) {
  for (final c in channels) {
    if (c.id == id) return c;
  }
  return null;
}

int _coerceChannelId(List<ChannelDto> channels, int wanted) {
  if (channels.isEmpty) return 0;
  if (_channelById(channels, wanted) != null) return wanted;
  return channels.first.id;
}

/// Bottom sheet ya kuongeza / kuhariri mechi — chagua chaneli (URL + picha), jina, beji ya LIVE.
Future<void> showLiveMatchSheet(
  BuildContext context,
  AdminStore store,
  LiveMatchDto? existing,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _LiveMatchBody(store: store, existing: existing),
  );
}

class _LiveMatchBody extends StatefulWidget {
  const _LiveMatchBody({required this.store, this.existing});

  final AdminStore store;
  final LiveMatchDto? existing;

  @override
  State<_LiveMatchBody> createState() => _LiveMatchBodyState();
}

class _LiveMatchBodyState extends State<_LiveMatchBody> {
  late final TextEditingController _idCtrl;
  late final TextEditingController _titleCtrl;
  late int _channelId;
  late bool _liveBadge;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final channels = widget.store.config.channels;
    _idCtrl = TextEditingController(text: e == null ? '${widget.store.nextLiveId()}' : '${e.id}');
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _channelId = _coerceChannelId(
      channels,
      e?.channelId ?? (channels.isEmpty ? 0 : channels.first.id),
    );
    _liveBadge = e?.liveBadge ?? true;
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Andika jina la mechi.')),
        );
      }
      return;
    }
    final channels = widget.store.config.channels;
    if (channels.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hakuna chaneli. Ongeza chaneli kwanza.')),
        );
      }
      return;
    }
    final id = int.tryParse(_idCtrl.text.trim()) ?? widget.store.nextLiveId();
    HapticFeedback.mediumImpact();
    await widget.store.upsertLive(
      LiveMatchDto(
        id: id,
        title: title,
        channelId: _channelId,
        liveBadge: _liveBadge,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final isNew = widget.existing == null;
    final channels = widget.store.config.channels;
    final selected = _channelById(channels, _channelId) ?? (channels.isEmpty ? null : channels.first);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0e1118),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.35),
                          cs.tertiary.withValues(alpha: 0.22),
                        ],
                      ),
                    ),
                    child: Icon(
                      isNew ? Icons.live_tv_rounded : Icons.sports_soccer_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isNew ? 'Mechi mpya' : 'Hariri mechi',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Chagua chaneli inayotiririsha — URL na picha zitatoka kwenye chaneli hiyo.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.06)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LiveSectionLabel(icon: Icons.tag_rounded, title: 'Kitambulisho'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _idCtrl,
                      enabled: isNew,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Nambari ya mechi',
                        hintText: 'Otomatiki kwa mechi mpya',
                        prefixIcon: Icon(Icons.numbers_rounded),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _LiveSectionLabel(icon: Icons.sports_rounded, title: 'Jina la mechi'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleCtrl,
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'K.m. Timu A vs Timu B',
                        hintText: 'Andika jina la mechi pekee',
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _LiveSectionLabel(icon: Icons.tv_rounded, title: 'Chaneli ya tiririsha'),
                    const SizedBox(height: 8),
                    Text(
                      'Chagua chaneli kutoka orodha — mtazamaji atapata stream na picha ya chaneli hiyo.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    if (channels.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: cs.error.withValues(alpha: 0.12),
                          border: Border.all(color: cs.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: cs.error),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Hakuna chaneli. Nenda kwenye Channels uongeze chaneli kwanza.',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      DropdownButtonFormField<int>(
                        value: selected?.id,
                        decoration: const InputDecoration(
                          labelText: 'Chagua chaneli',
                          prefixIcon: Icon(Icons.play_circle_outline_rounded),
                        ),
                        borderRadius: BorderRadius.circular(14),
                        items: [
                          for (final c in channels)
                            DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                '${c.name} (ID ${c.id})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _channelId = v);
                        },
                      ),
                      if (selected != null) ...[
                        const SizedBox(height: 16),
                        _ChannelPreviewCard(channel: selected),
                      ],
                    ],
                    const SizedBox(height: 24),
                    _LiveSectionLabel(icon: Icons.fiber_manual_record_rounded, title: 'Beji'),
                    const SizedBox(height: 12),
                    _LiveBadgeToggleCard(
                      value: _liveBadge,
                      onChanged: (v) => setState(() => _liveBadge = v),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: channels.isEmpty ? null : _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        isNew ? 'Ongeza mechi' : 'Hifadhi mabadiliko',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelPreviewCard extends StatelessWidget {
  const _ChannelPreviewCard({required this.channel});

  final ChannelDto channel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = channel.url.trim();
    final urlShort = url.isEmpty ? '(Hakuna URL bado — weka kwenye Channel)' : (url.length > 56 ? '${url.substring(0, 56)}…' : url);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF161c28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 44,
              child: Image.network(
                channel.img,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.image_not_supported_outlined, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 6),
                Text(
                  urlShort,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11.5,
                    height: 1.3,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadgeToggleCard extends StatelessWidget {
  const _LiveBadgeToggleCard({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF161c28),
        border: Border.all(
          color: value ? const Color(0xFFef4444).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.08),
          width: value ? 1.5 : 1,
        ),
        boxShadow: value
            ? [
                BoxShadow(
                  color: const Color(0xFFef4444).withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: value ? const Color(0xFFef4444).withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.06),
            ),
            child: Text(
              'LIVE',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1,
                color: value ? Colors.white : Colors.white54,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Beji ya LIVE',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.2),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'Itaonekana kama mechi inayocheza sasa'
                      : 'Ficha beji ya LIVE kwenye kadi',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LiveSectionLabel extends StatelessWidget {
  const _LiveSectionLabel({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: cs.primary.withValues(alpha: 0.95),
          ),
        ),
      ],
    );
  }
}
