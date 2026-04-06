import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// EaAdmin-style: API + `X-Admin-Key` are compiled into the app (dart-define or [admin_api_config]).
/// No password/C sign-in required for day-to-day edits.
class _ServerSyncCard extends StatefulWidget {
  @override
  State<_ServerSyncCard> createState() => _ServerSyncCardState();
}

class _ServerSyncCardState extends State<_ServerSyncCard> {
  late final TextEditingController _advancedBase = TextEditingController();
  late final TextEditingController _jwtPassword = TextEditingController();
  bool _seededAdvancedBase = false;
  bool _advancedOpen = false;

  @override
  void dispose() {
    _advancedBase.dispose();
    _jwtPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final cs = Theme.of(context).colorScheme;

    if (!_seededAdvancedBase && store.isLoaded) {
      _seededAdvancedBase = true;
      _advancedBase.text = store.resolvedApiBaseUrl;
    }

    final bundledKeyOk = store.resolvedAdminApiKey.isNotEmpty;
    final jwtOk = store.resolvedAdminToken.isNotEmpty;

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
              Icon(Icons.cloud_sync_rounded, color: cs.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cloud sync (Postgres)',
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
            'Kama EaAdmin: nenosiri/API hazionyeshwi hapa. Funguo ya msimamizi iko ndani ya APK (ADMIN_API_KEY sawa na Railway). Mabadiliko yanaenda Postgres moja kwa moja; app ya mtazamaji inasoma /public/config.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          _StatusRow(
            ok: bundledKeyOk,
            label: bundledKeyOk ? 'Admin key: configured' : 'Admin key: missing — rebuild with --dart-define=ADMIN_API_KEY=…',
          ),
          const SizedBox(height: 6),
          _StatusRow(
            ok: jwtOk,
            label: jwtOk ? 'JWT session: active (optional)' : 'JWT: not used (optional fallback)',
            mutedWhenOk: true,
          ),
          const SizedBox(height: 10),
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
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
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
          const SizedBox(height: 12),
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
                            SnackBar(content: Text(msg == null ? 'Health OK.' : msg)),
                          );
                        },
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: const Text('Test API'),
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
                                msg == null ? 'Database OK.' : msg,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.storage_rounded, size: 18),
                  label: const Text('Test DB'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: store.syncingToServer || !store.hasAdminSession
                      ? null
                      : () async {
                          await adminWithShimmerDialog(
                            context,
                            future: context.read<AdminStore>().syncNowToServer(),
                            message: 'Pushing to DB…',
                          );
                          if (context.mounted) {
                            final err = context.read<AdminStore>().lastSyncError;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(err == null ? 'Synced to Postgres.' : err)),
                            );
                          }
                        },
                  icon: const Icon(Icons.cloud_upload_rounded),
                  label: const Text('Push to DB'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: store.syncingToServer || !store.hasAdminSession
                      ? null
                      : () async {
                          await adminWithShimmerDialog(
                            context,
                            future: context.read<AdminStore>().pullConfigFromServer(),
                            message: 'Loading from DB…',
                          );
                          if (!context.mounted) return;
                          final err = context.read<AdminStore>().lastSyncError;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err == null ? 'Loaded from server.' : err),
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        },
                  icon: Icon(Icons.cloud_download_rounded, size: 20, color: cs.primary),
                  label: Text('Reload', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              title: Text(
                'Advanced',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              initiallyExpanded: _advancedOpen,
              onExpansionChanged: (v) => setState(() => _advancedOpen = v),
              children: [
                TextField(
                  controller: _advancedBase,
                  decoration: const InputDecoration(
                    labelText: 'Override API URL',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: store.syncingToServer
                      ? null
                      : () async {
                          await context.read<AdminStore>().saveApiBaseUrl(_advancedBase.text.trim());
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('API URL saved.')),
                            );
                          }
                        },
                  child: const Text('Save URL'),
                ),
                const SizedBox(height: 16),
                Text(
                  'JWT sign-in (Railway ADMIN_APP_PASSWORD + JWT_SECRET) if you prefer not to use ADMIN_API_KEY in the app.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _jwtPassword,
                  decoration: const InputDecoration(
                    labelText: 'Admin password (JWT)',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                  obscureText: true,
                  autocorrect: false,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: store.syncingToServer
                            ? null
                            : () async {
                                await adminWithShimmerDialog(
                                  context,
                                  future: context.read<AdminStore>().loginWithPassword(_jwtPassword.text),
                                  message: 'Signing in…',
                                );
                                if (context.mounted) {
                                  final err = context.read<AdminStore>().lastSyncError;
                                  final ok = context.read<AdminStore>().resolvedAdminToken.isNotEmpty;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok
                                            ? (err == null ? 'JWT session started.' : 'Signed in; load: $err')
                                            : (err ?? 'Check password.'),
                                      ),
                                      duration: const Duration(seconds: 4),
                                    ),
                                  );
                                }
                              },
                        child: const Text('Sign in (JWT)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: store.syncingToServer
                          ? null
                          : () async {
                              await context.read<AdminStore>().logout();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('JWT cleared.')),
                                );
                              }
                            },
                      child: const Text('Clear JWT'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.ok,
    required this.label,
    this.mutedWhenOk = false,
  });

  final bool ok;
  final String label;
  final bool mutedWhenOk;

  @override
  Widget build(BuildContext context) {
    final icon = ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded;
    final color = ok
        ? (mutedWhenOk
            ? Colors.white.withValues(alpha: 0.35)
            : Theme.of(context).colorScheme.primary)
        : Colors.amber;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: ok && !mutedWhenOk ? Colors.white.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
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
