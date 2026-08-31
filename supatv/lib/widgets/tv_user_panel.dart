import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/theme/brand_palette.dart';
import 'package:supatv/models/tv_playback_settings.dart';

/// Top-right menu: User ID + playback quality.
class TvUserPanel extends StatefulWidget {
  const TvUserPanel({super.key, required this.onClose, this.onOpenPremium});

  final VoidCallback onClose;
  final VoidCallback? onOpenPremium;

  @override
  State<TvUserPanel> createState() => _TvUserPanelState();
}

class _TvUserPanelState extends State<TvUserPanel> {
  String _userId = '…';
  bool _premium = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final id = await UserIdentity.getOrCreatePublicId();
    if (mounted) {
      setState(() {
        _userId = id;
        _premium = SubscriptionStore.isPremiumActiveLocal();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TvPlaybackSettings>();

    return Material(
      color: Colors.black54,
      child: GestureDetector(
        onTap: widget.onClose,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                color: BrandPalette.bgMid,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Akaunti',
                            style: TextStyle(
                              color: BrandPalette.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: widget.onClose,
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _InfoTile(label: 'User ID', value: _userId),
                      const SizedBox(height: 14),
                      Text(
                        _premium ? 'Premium inaendelea' : 'Bila premium',
                        style: TextStyle(
                          color: _premium ? const Color(0xFF34D399) : Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!_premium && widget.onOpenPremium != null) ...[
                        const SizedBox(height: 14),
                        _MalipoCta(onPressed: widget.onOpenPremium!),
                      ],
                      const SizedBox(height: 20),
                      const Text(
                        'Ubora wa video',
                        style: TextStyle(
                          color: BrandPalette.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final q in TvPlaybackSettings.options)
                            ChoiceChip(
                              label: Text(q),
                              selected: settings.qualityLabel == q,
                              onSelected: (_) => settings.setQuality(q),
                              selectedColor: BrandPalette.accent.withValues(alpha: 0.35),
                              labelStyle: TextStyle(
                                color: settings.qualityLabel == q
                                    ? BrandPalette.white
                                    : Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                              side: BorderSide(
                                color: settings.qualityLabel == q
                                    ? BrandPalette.accent
                                    : Colors.white24,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MalipoCta extends StatelessWidget {
  const _MalipoCta({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4ADE80), Color(0xFF22C55E), Color(0xFF15803D)],
            stops: [0.0, 0.5, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF22C55E).withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payments_rounded, color: Colors.white.withValues(alpha: 0.95), size: 28),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Malipo',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.98),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        'Fungua channel zote',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_rounded, color: Colors.white.withValues(alpha: 0.9), size: 26),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: BrandPalette.bgDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const Spacer(),
          SelectableText(
            value,
            style: const TextStyle(
              color: BrandPalette.accent,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User ID imenakiliwa'), duration: Duration(seconds: 2)),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
