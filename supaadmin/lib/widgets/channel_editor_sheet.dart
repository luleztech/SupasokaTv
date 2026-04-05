import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_config.dart';
import '../store/admin_store.dart';

/// Pro bottom sheet for add / edit channel.
Future<void> showChannelEditorSheet(
  BuildContext context,
  AdminStore store,
  ChannelDto? existing,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ChannelEditorBody(store: store, existing: existing),
  );
}

class _ChannelEditorBody extends StatefulWidget {
  const _ChannelEditorBody({required this.store, this.existing});

  final AdminStore store;
  final ChannelDto? existing;

  @override
  State<_ChannelEditorBody> createState() => _ChannelEditorBodyState();
}

class _ChannelEditorBodyState extends State<_ChannelEditorBody> {
  late final TextEditingController _idCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _imgCtrl;
  late final TextEditingController _viewersCtrl;
  late final TextEditingController _clearKeyCtrl;
  late String _cat;
  late String _drm;
  late bool _premiumOnly;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _idCtrl = TextEditingController(text: e?.id.toString() ?? '${widget.store.nextChannelId()}');
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _urlCtrl = TextEditingController(text: e?.url ?? '');
    _imgCtrl = TextEditingController(text: e?.img ?? '');
    _viewersCtrl = TextEditingController(text: e?.viewers ?? '0');
    _clearKeyCtrl = TextEditingController(text: e?.clearKeyKidKey ?? '');
    _cat = normalizeChannelCategory(e?.cat ?? 'movies');
    _drm = normalizeChannelDrm(e?.drm);
    _premiumOnly = e != null ? !e.free : false;
    _enabled = e?.enabled ?? true;
    _imgCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _imgCtrl.dispose();
    _viewersCtrl.dispose();
    _clearKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = int.tryParse(_idCtrl.text.trim());
    if (id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid channel ID')));
      }
      return;
    }
    if (_drm == 'clearkey') {
      final ck = _clearKeyCtrl.text.trim();
      final colon = ck.indexOf(':');
      if (colon <= 0 || colon >= ck.length - 1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ClearKey: enter kid:key (one colon between KID and key).'),
            ),
          );
        }
        return;
      }
    }
    HapticFeedback.mediumImpact();
    final clearKey = _drm == 'clearkey' ? _clearKeyCtrl.text.trim() : '';
    await widget.store.upsertChannel(
      ChannelDto(
        id: id,
        name: _nameCtrl.text.trim(),
        cat: _cat,
        img: _imgCtrl.text.trim(),
        free: !_premiumOnly,
        viewers: _viewersCtrl.text.trim().isEmpty ? '0' : _viewersCtrl.text.trim(),
        url: _urlCtrl.text.trim(),
        enabled: _enabled,
        drm: _drm,
        clearKeyKidKey: clearKey,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final isNew = widget.existing == null;

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
                    child: Icon(isNew ? Icons.add_rounded : Icons.edit_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isNew ? 'New channel' : 'Edit channel',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                        ),
                        Text(
                          'Stream · DRM · Mpira/Movies/Habari · Premium · Active',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
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
                    _SectionLabel(icon: Icons.tag_rounded, title: 'Identity'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _idCtrl,
                      enabled: isNew,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Channel ID',
                        hintText: 'Unique number',
                        prefixIcon: Icon(Icons.numbers_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Channel name',
                        prefixIcon: Icon(Icons.tv_rounded),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel(icon: Icons.link_rounded, title: 'Stream URL'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _urlCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Playback / stream URL',
                        hintText: 'https://…',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.movie_filter_rounded),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel(icon: Icons.lock_rounded, title: 'DRM'),
                    const SizedBox(height: 10),
                    Text(
                      'Some streams need ClearKey or Widevine. Pick None if the URL is open.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final e in kChannelDrmOptions.entries)
                          _CategoryChip(
                            label: e.value,
                            selected: _drm == e.key,
                            onTap: () => setState(() => _drm = e.key),
                          ),
                      ],
                    ),
                    if (_drm == 'clearkey') ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: _clearKeyCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'ClearKey kid:key',
                          hintText: 'hex-or-base64-kid:hex-or-base64-key',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(Icons.key_rounded),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _SectionLabel(icon: Icons.category_rounded, title: 'Category'),
                    const SizedBox(height: 10),
                    Text(
                      'Mpira · Movies · Habari — filters in the viewer app.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final e in kChannelCategoryOptions.entries)
                          _CategoryChip(
                            label: e.value,
                            selected: _cat == e.key,
                            onTap: () => setState(() => _cat = e.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel(icon: Icons.workspace_premium_rounded, title: 'Access'),
                    const SizedBox(height: 10),
                    _ToggleCard(
                      title: 'Premium',
                      subtitle: _premiumOnly
                          ? 'Subscription required to watch'
                          : 'Free for all viewers',
                      value: _premiumOnly,
                      onChanged: (v) => setState(() => _premiumOnly = v),
                      activeColor: const Color(0xFFFFD700),
                      icon: Icons.workspace_premium_rounded,
                    ),
                    const SizedBox(height: 12),
                    _ToggleCard(
                      title: 'Active',
                      subtitle: _enabled ? 'Visible in the app' : 'Hidden — channel disabled',
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                      activeColor: cs.primary,
                      icon: Icons.power_settings_new_rounded,
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel(icon: Icons.image_rounded, title: 'Thumbnail'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _imgCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Thumbnail image URL',
                        hintText: 'Poster artwork URL',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.image_outlined),
                      ),
                    ),
                    if (_imgCtrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(
                            _imgCtrl.text.trim(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: cs.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _SectionLabel(icon: Icons.visibility_rounded, title: 'Stats label'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _viewersCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Viewers (display)',
                        hintText: '24.1K',
                        prefixIcon: Icon(Icons.groups_rounded),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Save channel', style: TextStyle(fontWeight: FontWeight.w800)),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.title});

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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.45),
                      cs.tertiary.withValues(alpha: 0.28),
                    ],
                  )
                : null,
            color: selected ? null : const Color(0xFF1a1f2e),
            border: Border.all(
              color: selected ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.activeColor,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF161c28),
        border: Border.all(
          color: value ? activeColor.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.08),
          width: value ? 1.5 : 1,
        ),
        boxShadow: value
            ? [
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: activeColor.withValues(alpha: value ? 0.22 : 0.08),
            ),
            child: Icon(icon, color: value ? activeColor : Colors.white54, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.3),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
