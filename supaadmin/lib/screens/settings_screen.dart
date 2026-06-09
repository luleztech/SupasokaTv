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
              child: const _CloudStatusCard(),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: StaggerEntrance(
              index: 2,
              child: const _PaymentProviderCard(),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverToBoxAdapter(
            child: StaggerEntrance(
              index: 4,
              slide: 12,
              child: _AppUpdateCard(
                forceUpdateEnabled: c.forceUpdateEnabled,
                minBuild: c.minAndroidBuild,
                minVersion: c.minAndroidVersion,
                latestVersion: c.latestAndroidVersion,
                latestBuild: c.latestAndroidBuild,
                playStoreUrl: c.playStoreUrl,
                onSave: ({
                  required forceUpdateEnabled,
                  required minBuild,
                  required minVersion,
                  required latestVersion,
                  required latestBuild,
                  required playStoreUrl,
                }) =>
                    context.read<AdminStore>().setAppUpdatePolicy(
                          forceUpdateEnabled: forceUpdateEnabled,
                          minAndroidBuild: minBuild,
                          minAndroidVersion: minVersion,
                          latestAndroidVersion: latestVersion,
                          latestAndroidBuild: latestBuild,
                          playStoreUrl: playStoreUrl,
                        ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentProviderCard extends StatefulWidget {
  const _PaymentProviderCard();

  @override
  State<_PaymentProviderCard> createState() => _PaymentProviderCardState();
}

class _PaymentProviderCardState extends State<_PaymentProviderCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<AdminStore>();
      if (store.hasAdminSession && !store.loadingPaymentProvider) {
        store.refreshPaymentProvider();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final isSonic = store.paymentProvider == 'sonicpesa';
    final activeColor = isSonic ? const Color(0xFF22c55e) : const Color(0xFF3b82f6);
    final apiReady = store.paymentProviderApiReady;
    final zenoReady = store.zenoConfigured;
    final sonicReady = store.sonicConfigured;
    final saving = store.savingPaymentProvider;
    final loading = store.loadingPaymentProvider;
    final loggedIn = store.hasAdminSession;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            activeColor.withValues(alpha: 0.18),
            const Color(0xFF7c3aed).withValues(alpha: 0.1),
            const Color(0xFF161a24),
          ],
        ),
        border: Border.all(
          color: activeColor.withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: activeColor.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 10),
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
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: activeColor.withValues(alpha: 0.22),
                ),
                child: Icon(Icons.account_balance_wallet_rounded, color: activeColor, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment gateway',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (loading || saving)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: activeColor),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _ProviderChip(
                label: 'ZenoPay',
                icon: Icons.flash_on_rounded,
                color: const Color(0xFF3b82f6),
                selected: !isSonic,
                enabled: !loading && !saving && loggedIn && apiReady && zenoReady,
                onTap: () => store.updatePaymentProvider('zeno'),
              ),
              const SizedBox(width: 10),
              _ProviderChip(
                label: 'SonicPesa',
                icon: Icons.speed_rounded,
                color: const Color(0xFF22c55e),
                selected: isSonic,
                enabled: !loading && !saving && loggedIn && apiReady && sonicReady,
                onTap: () => store.updatePaymentProvider('sonicpesa'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (enabled == true) ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected ? color.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.04),
              border: Border.all(
                color: selected ? color.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.08),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, color: selected ? color : Colors.white54, size: 22),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: selected ? Colors.white : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloudStatusCard extends StatefulWidget {
  const _CloudStatusCard();

  @override
  State<_CloudStatusCard> createState() => _CloudStatusCardState();
}

class _CloudStatusCardState extends State<_CloudStatusCard> {

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _save(BuildContext context) async {
    final store = context.read<AdminStore>();
    await store.saveRuntimeSyncSettings(
      jwt: store.runtimeAdminApiKeyForEditing,
    );
    if (!context.mounted) return;
    final err = store.lastSyncError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err == null || err.isEmpty ? 'Imehifadhiwa; data yamepakiwa kutoka server.' : err,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final cs = Theme.of(context).colorScheme;
    final ok = store.hasAdminSession;
    final saving = store.syncingToServer;

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
              Icon(Icons.storage_rounded, color: ok ? cs.primary : Colors.amber, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Backend',
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: store.syncingToServer
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: store.resolvedApiBaseUrl));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('API URL nakala')),
                            );
                          }
                        },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Nakili URL'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: saving ? null : () => _save(context),
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(saving ? 'Saving...' : 'Save'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: ok ? () => context.read<AdminStore>().logout() : null,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logout'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cs.error),
                  foregroundColor: cs.error,
                ),
              ),
            ],
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
    final store = context.watch<AdminStore>();
    final saving = store.syncingToServer;
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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(spellCheckConfiguration: SpellCheckConfiguration.disabled(),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'WhatsApp number',
              prefixIcon: Icon(Icons.phone_android_rounded),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _AppUpdateCard extends StatefulWidget {
  const _AppUpdateCard({
    required this.forceUpdateEnabled,
    required this.minBuild,
    required this.minVersion,
    required this.latestVersion,
    required this.latestBuild,
    required this.playStoreUrl,
    required this.onSave,
  });

  final bool forceUpdateEnabled;
  final int minBuild;
  final String minVersion;
  final String latestVersion;
  final int latestBuild;
  final String playStoreUrl;
  final Future<void> Function({
    required bool forceUpdateEnabled,
    required int minBuild,
    required String minVersion,
    required String latestVersion,
    required int latestBuild,
    required String playStoreUrl,
  }) onSave;

  @override
  State<_AppUpdateCard> createState() => _AppUpdateCardState();
}

class _AppUpdateCardState extends State<_AppUpdateCard> {
  late bool _forceUpdate = widget.forceUpdateEnabled;
  bool _saving = false;
  bool _editing = false;
  late final TextEditingController _buildCtrl =
      TextEditingController(text: widget.minBuild > 0 ? '${widget.minBuild}' : '');
  late final TextEditingController _versionCtrl = TextEditingController(text: widget.minVersion);
  late final TextEditingController _latestVersionCtrl =
      TextEditingController(text: widget.latestVersion);
  late final TextEditingController _latestBuildCtrl =
      TextEditingController(text: widget.latestBuild > 0 ? '${widget.latestBuild}' : '');
  late final TextEditingController _storeCtrl = TextEditingController(text: widget.playStoreUrl);

  @override
  void initState() {
    super.initState();
    for (final c in [_buildCtrl, _versionCtrl, _latestVersionCtrl, _latestBuildCtrl, _storeCtrl]) {
      c.addListener(_markEditing);
    }
  }

  void _markEditing() {
    if (!_editing && mounted) setState(() => _editing = true);
  }

  @override
  void didUpdateWidget(covariant _AppUpdateCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_saving || _editing) return;
    _forceUpdate = widget.forceUpdateEnabled;
    _buildCtrl.text = widget.minBuild > 0 ? '${widget.minBuild}' : '';
    _versionCtrl.text = widget.minVersion;
    _latestVersionCtrl.text = widget.latestVersion;
    _latestBuildCtrl.text = widget.latestBuild > 0 ? '${widget.latestBuild}' : '';
    _storeCtrl.text = widget.playStoreUrl;
  }

  @override
  void dispose() {
    for (final c in [_buildCtrl, _versionCtrl, _latestVersionCtrl, _latestBuildCtrl, _storeCtrl]) {
      c.removeListener(_markEditing);
    }
    _buildCtrl.dispose();
    _versionCtrl.dispose();
    _latestVersionCtrl.dispose();
    _latestBuildCtrl.dispose();
    _storeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _editing = false;
    });
    try {
      final build = int.tryParse(_buildCtrl.text.trim()) ?? 0;
      final latestBuild = int.tryParse(_latestBuildCtrl.text.trim()) ?? 0;
      await widget.onSave(
        forceUpdateEnabled: _forceUpdate,
        minBuild: build,
        minVersion: _versionCtrl.text.trim(),
        latestVersion: _latestVersionCtrl.text.trim(),
        latestBuild: latestBuild,
        playStoreUrl: _storeCtrl.text.trim(),
      );
      if (!mounted) return;
      final err = context.read<AdminStore>().lastSyncError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err == null || err.isEmpty ? 'Sera ya update imehifadhiwa' : err,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();
    final saving = _saving || store.savingAppUpdatePolicy;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFe8002d).withValues(alpha: 0.16),
            const Color(0xFF161a24),
          ],
        ),
        border: Border.all(color: const Color(0xFFe8002d).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.system_update_alt_rounded, color: Color(0xFFfb7185)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Lazima ku update app',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _forceUpdate,
            onChanged: saving
                ? null
                : (v) => setState(() {
                      _forceUpdate = v;
                      _editing = true;
                    }),
            title: const Text('Lazima ku update app'),
          ),
          const SizedBox(height: 8),
          TextField(
            spellCheckConfiguration: SpellCheckConfiguration.disabled(),
            controller: _buildCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Build ya chini (versionCode)',
              hintText: '14',
              prefixIcon: Icon(Icons.numbers_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            spellCheckConfiguration: SpellCheckConfiguration.disabled(),
            controller: _versionCtrl,
            decoration: const InputDecoration(
              labelText: 'Toleo la chini',
              hintText: '1.1.8',
              prefixIcon: Icon(Icons.new_releases_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            spellCheckConfiguration: SpellCheckConfiguration.disabled(),
            controller: _latestVersionCtrl,
            decoration: const InputDecoration(
              labelText: 'Toleo jipya',
              hintText: '1.2.0',
              prefixIcon: Icon(Icons.upgrade_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            spellCheckConfiguration: SpellCheckConfiguration.disabled(),
            controller: _latestBuildCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Build jipya (hiari)',
              hintText: '14',
              prefixIcon: Icon(Icons.build_circle_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            spellCheckConfiguration: SpellCheckConfiguration.disabled(),
            controller: _storeCtrl,
            decoration: const InputDecoration(
              labelText: 'Play Store URL',
              prefixIcon: Icon(Icons.shop_rounded),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(saving ? 'Inahifadhi…' : 'Hifadhi sera ya update'),
          ),
        ],
      ),
    );
  }
}
