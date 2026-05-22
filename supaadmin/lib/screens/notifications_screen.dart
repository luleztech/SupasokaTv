import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../admin_messenger.dart';
import '../models/app_config.dart';
import '../store/admin_store.dart';
import '../widgets/admin_page_header.dart';
import '../widgets/stagger_entrance.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static const _audienceOptions = ['all', 'premium', 'free'];

  static String _normalizeAudienceForDropdown(String target) {
    final t = target.trim().toLowerCase();
    if (_audienceOptions.contains(t)) return t;
    return 'all';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final log = store.config.notificationLog;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StaggerEntrance(
            index: 0,
            child: AdminPageHeader(
              title: 'Push notifications',
              icon: Icons.notifications_active_rounded,
              actions: [
                OutlinedButton.icon(
                  onPressed: () => _checkPushHealth(context, store),
                  icon: const Icon(Icons.health_and_safety_rounded),
                  label: const Text('Check push'),
                ),
                FilledButton.icon(
                  onPressed: () => _openComposer(context, store),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Tuma ujumbe'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('History', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Expanded(
            child: log.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_off_rounded, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        Text('No notifications yet', style: TextStyle(color: Colors.white.withValues(alpha: 0.45))),
                      ],
                    ),
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: log.length,
                    separatorBuilder: (context, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final n = log[i];
                      return StaggerEntrance(
                        index: i,
                        child: Dismissible(
                          key: ValueKey(n.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.25),
                            ),
                            child: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                          ),
                          onDismissed: (_) => store.deleteNotification(n.id),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openComposer(context, store, from: n),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF161a24),
                                      Color(0xFF12151c),
                                    ],
                                  ),
                                ),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                                          ),
                                          child: Text(
                                            n.target.toUpperCase(),
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                                          ),
                                        ),
                                        const Spacer(),
                                        OutlinedButton.icon(
                                          onPressed: () => _openComposer(context, store, from: n),
                                          icon: const Icon(Icons.replay_rounded, size: 18),
                                          label: const Text('Tuma tena'),
                                          style: OutlinedButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          tooltip: 'Futa',
                                          icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                          onPressed: () => store.deleteNotification(n.id),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                    const SizedBox(height: 6),
                                    Text(
                                      n.body,
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.65), height: 1.35),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      n.createdAt,
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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

  Future<void> _openComposer(
    BuildContext context,
    AdminStore store, {
    NotificationEntryDto? from,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => _NotificationComposerDialog(
        store: store,
        from: from,
        parentContext: context,
      ),
    );
  }

  Future<void> _checkPushHealth(BuildContext context, AdminStore store) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Checking push configuration...')),
          ],
        ),
      ),
    );
    try {
      final msg = await store.checkPushHealth();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Push check failed: ${adminFormatError(e)}')),
      );
    }
  }
}

class _NotificationComposerDialog extends StatefulWidget {
  const _NotificationComposerDialog({
    required this.store,
    required this.parentContext,
    this.from,
  });

  final AdminStore store;
  final BuildContext parentContext;
  final NotificationEntryDto? from;

  @override
  State<_NotificationComposerDialog> createState() => _NotificationComposerDialogState();
}

class _NotificationComposerDialogState extends State<_NotificationComposerDialog> {
  static const _audienceOptions = NotificationsScreen._audienceOptions;

  late final TextEditingController _title;
  late final TextEditingController _body;
  late String _target;
  bool _sending = false;

  bool get _isResend => widget.from != null;

  String get _originalTarget => widget.from?.target.trim() ?? '';

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.from?.title ?? '');
    _body = TextEditingController(text: widget.from?.body ?? '');
    _target = NotificationsScreen._normalizeAudienceForDropdown(widget.from?.target ?? 'all');
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final saved = await widget.store.sendNotification(
        title: _title.text.trim(),
        body: _body.text.trim(),
        target: _target,
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (!widget.parentContext.mounted) return;
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Imehifadhiwa na kutumwa.'
                : 'Ujumbe umetumwa, lakini historia haijahifadhiwa kwenye seva.',
          ),
        ),
      );
    } catch (e) {
      if (!widget.parentContext.mounted) return;
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        SnackBar(content: Text('Imeshindikana kutuma: ${adminFormatError(e)}')),
      );
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isResend ? 'Hariri na tuma tena' : 'Tuma ujumbe'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isResend &&
                _originalTarget.isNotEmpty &&
                !_audienceOptions.contains(_originalTarget.toLowerCase())) ...[
              Text(
                'Asili: $_originalTarget',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              spellCheckConfiguration: SpellCheckConfiguration.disabled(),
              controller: _title,
              decoration: const InputDecoration(labelText: 'Kichwa'),
            ),
            const SizedBox(height: 12),
            TextField(
              spellCheckConfiguration: SpellCheckConfiguration.disabled(),
              controller: _body,
              decoration: const InputDecoration(labelText: 'Ujumbe'),
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Wateja'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _target,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Wote')),
                    DropdownMenuItem(value: 'premium', child: Text('Premium tu')),
                    DropdownMenuItem(value: 'free', child: Text('Bure tu')),
                  ],
                  onChanged: _sending ? null : (v) => setState(() => _target = v ?? 'all'),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Ghairi'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(_sending ? 'Inatuma...' : 'Tuma sasa'),
        ),
      ],
    );
  }
}
