import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:url_launcher/url_launcher.dart';

class ForceUpdateScreen extends StatefulWidget {
  const ForceUpdateScreen({
    super.key,
    required this.currentVersion,
    required this.currentBuild,
    required this.minVersion,
    required this.latestVersion,
    required this.minBuild,
    required this.latestBuild,
    required this.playStoreUrl,
    required this.onRecheck,
  });

  final String currentVersion;
  final int currentBuild;
  final String minVersion;
  final String latestVersion;
  final int minBuild;
  final int latestBuild;
  final String playStoreUrl;
  final Future<void> Function() onRecheck;

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  bool _checking = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _openStore() async {
    final uri = Uri.parse(widget.playStoreUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _recheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await widget.onRecheck();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String get _requiredLabel {
    if (widget.latestVersion.isNotEmpty) {
      final buildSuffix = widget.latestBuild > 0 ? ' (build ${widget.latestBuild})' : '';
      return 'Toleo ${widget.latestVersion}$buildSuffix';
    }
    if (widget.minBuild > 0) {
      return 'Toleo ${widget.minVersion.isNotEmpty ? widget.minVersion : ''} (build ${widget.minBuild})'.trim();
    }
    if (widget.minVersion.isNotEmpty) return 'Toleo ${widget.minVersion}';
    return 'Toleo jipya';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final top = MediaQuery.paddingOf(context).top;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: t.bg1,
        body: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 1.1,
                  colors: [
                    t.accent.withValues(alpha: 0.18),
                    t.bg1,
                    t.bg1,
                  ],
                ),
              ),
            ),
            Positioned(
              top: -80,
              right: -40,
              child: Icon(Ionicons.sparkles, size: 220, color: t.accent.withValues(alpha: 0.05)),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, top > 0 ? 12 : 24, 24, 24),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                          colors: [t.accent, t.accent2],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: t.glow.withValues(alpha: 0.45),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(Ionicons.arrow_up_circle, size: 42, color: Colors.white.withValues(alpha: 0.96)),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Update app yako',
                      textAlign: TextAlign.center,
                      style: inter(28, weight: FontWeight.w900).copyWith(
                        color: t.text,
                        letterSpacing: -0.8,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Toleo jipya la Supasoka limeshapatikana. Update app yako ili uendelee kutazama live, channel zote, na vipengele vipya. Bila update huwezi kufungua live session.',
                      textAlign: TextAlign.center,
                      style: rajdhani(15, weight: FontWeight.w600).copyWith(
                        color: t.text2,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: t.card.withValues(alpha: 0.55),
                        border: Border.all(color: t.border.withValues(alpha: 0.45)),
                      ),
                      child: Column(
                        children: [
                          _VersionRow(
                            label: 'App yako sasa',
                            value: 'v${widget.currentVersion} (${widget.currentBuild})',
                            muted: true,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Divider(color: t.border.withValues(alpha: 0.35), height: 1),
                          ),
                          if (widget.minVersion.isNotEmpty && widget.minVersion != widget.latestVersion)
                            _VersionRow(
                              label: 'Min version',
                              value: widget.minVersion,
                              muted: true,
                            ),
                          if (widget.minVersion.isNotEmpty && widget.minVersion != widget.latestVersion)
                            const SizedBox(height: 8),
                          _VersionRow(
                            label: 'Latest version',
                            value: _requiredLabel,
                            accent: t.accent2,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(flex: 3),
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) {
                        final glow = 0.28 + _pulse.value * 0.2;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              colors: [t.accent, t.accent2],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: t.glow.withValues(alpha: glow),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: _openStore,
                              child: Ink(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Ionicons.logo_google_playstore, color: Colors.white, size: 22),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Update app yako',
                                      style: inter(16, weight: FontWeight.w800).copyWith(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _checking ? null : _recheck,
                      icon: _checking
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: t.text2),
                            )
                          : Icon(Ionicons.refresh_outline, size: 18, color: t.text2),
                      label: Text(
                        _checking ? 'Inakagua…' : 'Nime-update app yako — kagua tena',
                        style: rajdhani(13, weight: FontWeight.w700).copyWith(color: t.text2),
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

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.label,
    required this.value,
    this.muted = false,
    this.accent,
  });

  final String label;
  final String value;
  final bool muted;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: rajdhani(12, weight: FontWeight.w700).copyWith(
              color: t.text2,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Text(
          value,
          style: inter(13, weight: FontWeight.w800).copyWith(
            color: accent ?? (muted ? t.text.withValues(alpha: 0.75) : t.text),
          ),
        ),
      ],
    );
  }
}
