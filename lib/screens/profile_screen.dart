import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/theme/brand_palette.dart';

String _avatarLetters(String publicId) {
  final tail =
      publicId.startsWith('User-') && publicId.length > 5 ? publicId.substring(5) : publicId;
  final alnum = tail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  if (alnum.length >= 2) return alnum.substring(0, 2).toUpperCase();
  if (alnum.isNotEmpty) return '${alnum[0]}•'.toUpperCase();
  return 'SK';
}

String _formatExpiryDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}';
}

String _countdownSwahili(Duration d) {
  if (d.isNegative) return 'Muda umeisha';
  var s = d.inSeconds;
  final days = s ~/ 86400;
  s -= days * 86400;
  final hours = s ~/ 3600;
  s -= hours * 3600;
  final minutes = s ~/ 60;
  final seconds = s % 60;
  return 'Umebakiwa na siku $days masaa $hours dakika $minutes na sekunde $seconds';
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _username;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    SubscriptionStore.premiumUntilNotifier.addListener(_onPremiumNotifier);
    _loadUsername();
    _syncCountdownTimer();
  }

  @override
  void dispose() {
    SubscriptionStore.premiumUntilNotifier.removeListener(_onPremiumNotifier);
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _onPremiumNotifier() {
    if (!mounted) return;
    setState(() {});
    _syncCountdownTimer();
  }

  Future<void> _loadUsername() async {
    final id = await UserIdentity.getOrCreatePublicId();
    if (!mounted) return;
    setState(() => _username = id);
  }

  void _syncCountdownTimer() {
    _countdownTimer?.cancel();
    final u = SubscriptionStore.premiumUntilNotifier.value;
    if (u != null && u.isAfter(DateTime.now())) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!mounted) return;
        final cur = SubscriptionStore.premiumUntilNotifier.value;
        if (cur == null || !cur.isAfter(DateTime.now())) {
          _countdownTimer?.cancel();
          await SubscriptionStore.purgeExpiredLocalPremium();
          await SubscriptionStore.syncPremiumFromBackend();
          if (!mounted) return;
          setState(() {});
          return;
        }
        setState(() {});
      });
    }
  }

  Future<void> _copyUsername() async {
    final id = _username?.trim();
    if (id == null || id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Jina lako limenakiliwa: $id', style: rajdhani(14, weight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: BrandPalette.bgMid,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = _username;
    final displayName = username ?? '...';
    final letters = username != null ? _avatarLetters(username) : 'SK';
    final top = MediaQuery.paddingOf(context).top;

    final until = SubscriptionStore.premiumUntilNotifier.value;
    final now = DateTime.now();
    final isPremium = until != null && until.isAfter(now);
    final remaining = until != null ? until.difference(now) : Duration.zero;

    return ColoredBox(
      color: BrandPalette.bgDeep,
      child: RefreshIndicator(
        color: BrandPalette.accent,
        backgroundColor: BrandPalette.bgMid,
        onRefresh: () => context.read<ContentStore>().refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, top + 16, 20, 100),
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 24,
                  decoration: const BoxDecoration(gradient: BrandPalette.activeGradient),
                ),
                const SizedBox(width: 10),
                Text(
                  'Akaunti yako',
                  style: rajdhani(18, weight: FontWeight.w800).copyWith(color: BrandPalette.white),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: BrandPalette.activeGradient,
                  boxShadow: [
                    BoxShadow(
                      color: BrandPalette.accent.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  letters,
                  style: orbitron(26, weight: FontWeight.w900).copyWith(color: BrandPalette.bgDeep),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: InkWell(
                onTap: username != null ? _copyUsername : null,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: orbitron(16).copyWith(color: BrandPalette.white, letterSpacing: 0.5),
                        ),
                      ),
                      if (username != null) ...[
                        const SizedBox(width: 8),
                        const Icon(Ionicons.copy_outline, size: 16, color: BrandPalette.accent),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _SubscriptionCard(
              isPremium: isPremium,
              remaining: remaining,
              expiryLabel: until != null ? _formatExpiryDate(until) : '',
            ),
            const SizedBox(height: 20),
            _MenuTile(
              icon: Ionicons.share_social_outline,
              title: 'Share App',
              subtitle: 'Invite your friends',
              onTap: () {},
            ),
            const SizedBox(height: 10),
            _MenuTile(
              icon: Ionicons.call_outline,
              title: 'Support',
              subtitle: 'Help & contact',
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.isPremium,
    required this.remaining,
    required this.expiryLabel,
  });

  final bool isPremium;
  final Duration remaining;
  final String expiryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: BrandPalette.bgMid.withValues(alpha: 0.85),
        border: Border.all(
          color: isPremium
              ? BrandPalette.accentWarm.withValues(alpha: 0.45)
              : BrandPalette.white.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPremium ? Ionicons.star : Ionicons.person_outline,
                size: 18,
                color: isPremium ? BrandPalette.accentWarm : BrandPalette.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Text(
                isPremium ? 'Premium User' : 'Free User',
                style: orbitron(12, weight: FontWeight.w800).copyWith(
                  color: isPremium ? BrandPalette.accentWarm : BrandPalette.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          if (isPremium) ...[
            const SizedBox(height: 14),
            Text(
              'Kifurushi kitaisha $expiryLabel',
              style: rajdhani(13, weight: FontWeight.w600).copyWith(color: BrandPalette.white.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 8),
            Text(
              _countdownSwahili(remaining),
              style: rajdhani(14, weight: FontWeight.w600).copyWith(color: BrandPalette.accent),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BrandPalette.bgMid.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: BrandPalette.activeGradient,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: BrandPalette.bgDeep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: rajdhani(14, weight: FontWeight.w700).copyWith(color: BrandPalette.white)),
                    Text(
                      subtitle,
                      style: rajdhani(11).copyWith(color: BrandPalette.white.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ),
              Icon(Ionicons.chevron_forward, size: 16, color: BrandPalette.white.withValues(alpha: 0.35)),
            ],
          ),
        ),
      ),
    );
  }
}
