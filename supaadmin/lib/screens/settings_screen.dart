import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/admin_api_config.dart';
import '../store/admin_store.dart';
import '../widgets/admin_page_header.dart';
import '../widgets/admin_shimmer.dart';
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
              child: _ServerSyncCard(),
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

/// API URL + admin password → JWT (no API key stored in the app).
class _ServerSyncCard extends StatefulWidget {
  @override
  State<_ServerSyncCard> createState() => _ServerSyncCardState();
}

class _ServerSyncCardState extends State<_ServerSyncCard> {
  late final TextEditingController _base = TextEditingController();
  late final TextEditingController _password = TextEditingController();
  bool _seededBase = false;

  @override
  void dispose() {
    _base.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final cs = Theme.of(context).colorScheme;
    if (!_seededBase && store.isLoaded) {
      _seededBase = true;
      _base.text = store.resolvedApiBaseUrl;
    }

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
              Icon(Icons.cloud_upload_rounded, color: cs.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sync to server (Postgres)',
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
          const SizedBox(height: 8),
          Text(
            'Nenosiri ni ADMIN_APP_PASSWORD kwenye Railway (si API key). Token ndiyo imehifadhiwa — si nenosiri. App ya mtazamaji: deployment.dart / API_BASE_URL iwe sawa na URL hii.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12, height: 1.4),
          ),
          if (store.hasAdminSession) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: cs.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Umeingia — token iko kwenye simu (siyo nenosiri).',
                    style: TextStyle(color: cs.primary.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _base,
            decoration: InputDecoration(
              labelText: 'API base URL',
              hintText: kDefaultAdminApiBaseUrl,
              prefixIcon: const Icon(Icons.link_rounded),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            decoration: const InputDecoration(
              labelText: 'Admin password',
              hintText: 'Railway env ADMIN_APP_PASSWORD',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
            obscureText: true,
            autocorrect: false,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
          ),
          if (store.lastSyncError != null) ...[
            const SizedBox(height: 10),
            Text(
              store.lastSyncError!,
              style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.9), fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: store.syncingToServer
                      ? null
                      : () async {
                          final msg = await context.read<AdminStore>().testApiUrlReachable();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                msg == null ? 'API URL inafunguka (health OK).' : msg,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: const Text('Test API URL'),
                ),
                TextButton.icon(
                  onPressed: store.syncingToServer
                      ? null
                      : () async {
                          final msg = await context.read<AdminStore>().testDatabaseReachable();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                msg == null
                                    ? 'Database imeunganishwa (SELECT 1 OK).'
                                    : msg,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.storage_rounded, size: 18),
                  label: const Text('Test database'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: store.syncingToServer
                      ? null
                      : () async {
                          await adminWithShimmerDialog(
                            context,
                            future: context.read<AdminStore>().saveUrlAndSignIn(
                                  apiBaseUrl: _base.text.trim().isEmpty ? kDefaultAdminApiBaseUrl : _base.text.trim(),
                                  password: _password.text,
                                ),
                            message: 'Inaingia na kupakia…',
                          );
                          if (context.mounted) {
                            final store = context.read<AdminStore>();
                            final err = store.lastSyncError;
                            final ok = store.hasAdminSession;
                            String msg;
                            if (!ok) {
                              msg = err ?? 'Weka nenosiri sahihi.';
                            } else if (err == null) {
                              msg = 'Imefanikiwa. Data zimepakishwa kutoka Postgres.';
                            } else {
                              msg = 'Umeingia lakini kupakia kumeshindikana: $err';
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
                            );
                          }
                        },
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Sign in & load from server'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: store.syncingToServer || !store.hasAdminSession
                    ? null
                    : () async {
                        await adminWithShimmerDialog(
                          context,
                          future: context.read<AdminStore>().syncNowToServer(),
                          message: 'Inatuma kwenye DB…',
                        );
                        if (context.mounted) {
                          final err = context.read<AdminStore>().lastSyncError;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err == null ? 'Imesawazishwa na Postgres.' : err),
                            ),
                          );
                        }
                      },
                child: const Text('Push to DB'),
              ),
            ],
          ),
          if (store.hasAdminSession) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: store.syncingToServer
                    ? null
                    : () async {
                        await context.read<AdminStore>().logout();
                        if (context.mounted) {
                          setState(() {
                            _password.clear();
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Umetoka — token imefutwa kwenye simu')),
                          );
                        }
                      },
                child: Text(
                  'Sign out',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                ),
              ),
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
    await adminWithShimmerDialog(
      context,
      future: widget.onSave(_phone.text),
      message: 'Saving…',
    );
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
                      'Weka namba ya huduma kwa wateja ya WhatsApp ukianza na +255 (mfano +255712345678).',
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
