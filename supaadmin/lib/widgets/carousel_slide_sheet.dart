import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_config.dart';
import '../store/admin_store.dart';

/// Full-screen style bottom sheet for add / edit home carousel slides.
Future<void> showCarouselSlideSheet(
  BuildContext context,
  AdminStore store,
  CarouselDto? existing,
  int index,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CarouselSlideBody(store: store, existing: existing, index: index),
  );
}

class _CarouselSlideBody extends StatefulWidget {
  const _CarouselSlideBody({
    required this.store,
    this.existing,
    required this.index,
  });

  final AdminStore store;
  final CarouselDto? existing;
  final int index;

  @override
  State<_CarouselSlideBody> createState() => _CarouselSlideBodyState();
}

class _CarouselSlideBodyState extends State<_CarouselSlideBody> {
  late final TextEditingController _badgeCtrl;
  late final TextEditingController _badgeIconCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _channelIdCtrl;
  late final TextEditingController _imgCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final defaultChannelId =
        e?.channelId ??
        (widget.store.config.channels.isEmpty ? 0 : widget.store.config.channels.first.id);
    _badgeCtrl = TextEditingController(text: e?.badge ?? 'NEW');
    _badgeIconCtrl = TextEditingController(text: e?.badgeIcon ?? 'radio-outline');
    _titleCtrl = TextEditingController(text: e?.title ?? 'Title\nLine 2');
    _channelIdCtrl = TextEditingController(text: '$defaultChannelId');
    _imgCtrl = TextEditingController(text: e?.img ?? 'https://');
    _imgCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _badgeCtrl.dispose();
    _badgeIconCtrl.dispose();
    _titleCtrl.dispose();
    _channelIdCtrl.dispose();
    _imgCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final channelId = int.tryParse(_channelIdCtrl.text.trim());
    if (channelId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Channel ID must be a number')),
        );
      }
      return;
    }
    HapticFeedback.mediumImpact();
    final dto = CarouselDto(
      badge: _badgeCtrl.text.trim(),
      badgeIcon: _badgeIconCtrl.text.trim(),
      title: _titleCtrl.text.trim(),
      channelId: channelId,
      img: _imgCtrl.text.trim(),
    );
    if (widget.existing == null) {
      await widget.store.addCarousel(dto);
    } else {
      await widget.store.upsertCarousel(widget.index, dto);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final isNew = widget.existing == null;

    final saving = context.watch<AdminStore>().syncingToServer;
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
                      isNew ? Icons.add_photo_alternate_rounded : Icons.view_carousel_rounded,
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
                          isNew ? 'New carousel slide' : 'Edit carousel slide',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hero image, headline, and which channel opens on Watch.',
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
                    _CarouselSectionLabel(icon: Icons.new_releases_rounded, title: 'On-air badge'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _badgeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Badge text',
                        hintText: 'LIVE NOW',
                        prefixIcon: Icon(Icons.label_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _badgeIconCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Badge icon key',
                        hintText: 'radio-outline',
                        prefixIcon: Icon(Icons.code_rounded),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _CarouselSectionLabel(icon: Icons.title_rounded, title: 'Headline'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'Line one\nLine two',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.short_text_rounded),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _CarouselSectionLabel(icon: Icons.touch_app_rounded, title: 'Watch action'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _channelIdCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Channel ID',
                        hintText: 'Matches a channel in your list',
                        prefixIcon: Icon(Icons.numbers_rounded),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _CarouselSectionLabel(icon: Icons.image_rounded, title: 'Hero artwork'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _imgCtrl,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Image URL',
                        hintText: 'https://…',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.link_rounded),
                      ),
                    ),
                    if (_imgCtrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
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
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: saving ? null : _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: saving
                          ? const SizedBox(
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              isNew ? 'Add slide' : 'Save slide',
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

class _CarouselSectionLabel extends StatelessWidget {
  const _CarouselSectionLabel({required this.icon, required this.title});

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
