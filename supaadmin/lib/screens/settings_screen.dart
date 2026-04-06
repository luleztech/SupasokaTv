import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../store/admin_store.dart';
import '../widgets/admin_page_header.dart';
import '../widgets/stagger_entrance.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final c = store.config;
    final cs = Theme.of(context).colorScheme;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(
            child: StaggerEntrance(
              index: 0,
              child: AdminPageHeader(
                title: 'Settings',
                icon: Icons.settings_rounded,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          sliver: SliverToBoxAdapter(
            child: StaggerEntrance(
              index: 1,
              child: _CloudStatusCard(),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: StaggerEntrance(
              index: 2,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFF161a24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: cs.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Config version v${c.configVersion}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverToBoxAdapter(
            child: StaggerEntrance(
              index: 3,
              slide: 12,
              child: _CustomerCareCard(
                digits: c.customerCareWhatsapp,
                onSave: (raw) => context.read<AdminStore>().setCustomerCareWhatsapp(raw),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CloudStatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final cs = Theme.of(context).colorScheme;
    final ok = store.hasAdminSession;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xFF161a24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_done_rounded, color: ok ? cs.primary : Colors.amber, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cloud',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (store.syncingToServer)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ok
                ? 'Mabadiliko yanaenda Postgres kiotomatiki. Hakuna nenosiri kwenye app — funguo iko kwenye msimbo (admin_api_config.dart) na Railway.'
                : 'Weka kRailwayAdminApiKey ndani ya supaadmin/lib/config/admin_api_config.dart iwe sawa na ADMIN_API_KEY kwenye Railway, kisha build APK upya.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: store.resolvedApiBaseUrl));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('API URL copied')),
                );
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 18, color: cs.primary.withValues(alpha: 0.85)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      store.resolvedApiBaseUrl,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                    ),
                  ),
                  Icon(Icons.copy_rounded, size: 16, color: Colors.white.withValues(alpha: 0.35)),
                ],
              ),
            ),
          ),
          if (store.lastSyncError != null) ...[
            const SizedBox(height: 10),
            Text(
              store.lastSyncError!,
              style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.9), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerCareCard extends StatefulWidget {
  const _CustomerCareCard({
    required this.digits,
    required this.onSave,
  });

  final String digits;
  final Future<void> Function(String raw) onSave;

  @override
  State<_CustomerCareCard> createState() => _CustomerCareCardState();
}

class _CustomerCareCardState extends State<_CustomerCareCard> {
  late final TextEditingController _phone = TextEditingController(text: widget.digits);

  @override
  void didUpdateWidget(covariant _CustomerCareCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.digits != oldWidget.digits) {
      _phone.text = widget.digits;
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.onSave(_phone.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imehifadhiwa')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF25d366).withValues(alpha: 0.12),
            cs.tertiary.withValues(alpha: 0.08),
            const Color(0xFF161a24).withValues(alpha: 0.95),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF25d366).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: const Color(0xFF25d366).withValues(alpha: 0.2),
                ),
                child: const Icon(Icons.support_agent_rounded, color: Color(0xFF25d366), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer care · WhatsApp',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Weka namba ya huduma kwa wateja ya WhatsApp.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'WhatsApp number',
              hintText: '+255712345678',
              prefixIcon: Icon(Icons.phone_android_rounded),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
