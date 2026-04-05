import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Broadcast message'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 12),
                TextField(controller: body, decoration: const InputDecoration(labelText: 'Body'), maxLines: 4),
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Record send')),
          ],
        ),
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      await store.sendNotification(title: title.text.trim(), body: body.text.trim(), target: target);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imehifadhiwa')),
        );
      }
    }
  }
}
