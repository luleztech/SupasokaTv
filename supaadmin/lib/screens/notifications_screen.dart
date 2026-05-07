import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../admin_messenger.dart';
import '../store/admin_store.dart';
import '../widgets/admin_page_header.dart';
import '../widgets/stagger_entrance.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

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
                  onPressed: () => _compose(context, store),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Compose'),
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
                              onTap: () {},
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
                                        IconButton(
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

  Future<void> _compose(BuildContext context, AdminStore store) async {
    final title = TextEditingController();
    final body = TextEditingController();
    var target = 'all';

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var sending = false;
        return StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Text('Broadcast message'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                    controller: body,
                    decoration: const InputDecoration(labelText: 'Body'),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Audience'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: target,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All users')),
                          DropdownMenuItem(value: 'premium', child: Text('Premium only')),
                          DropdownMenuItem(value: 'free', child: Text('Free only')),
                        ],
                        onChanged: (v) => setSt(() => target = v ?? 'all'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: sending ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: sending
                    ? null
                    : () async {
                        if (title.text.trim().isEmpty) return;
                        setSt(() => sending = true);
                        try {
                          final saved = await store.sendNotification(
                            title: title.text.trim(),
                            body: body.text.trim(),
                            target: target,
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                saved
                                    ? 'Imehifadhiwa na kutumwa.'
                                    : 'Ujumbe umetumwa, lakini historia haijahifadhiwa kwenye seva. Jaribu tena baada ya muda mfupi.',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Imeshindikana kutuma: ${adminFormatError(e)}')),
                          );
                        } finally {
                          if (ctx.mounted) {
                            setSt(() => sending = false);
                          }
                        }
                      },
                child: sending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Record send'),
              ),
            ],
          ),
        );
      },
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
