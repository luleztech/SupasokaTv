import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/screens/settings_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/widgets/app_header.dart';

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
          await SubscriptionStore.refreshNotifierFromPrefs();
          if (!mounted) return;
          setState(() {});
          return;
        }
        setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final username = _username;
    final displayName = username ?? '...';
    final letters = username != null ? _avatarLetters(username) : 'SK';

    final until = SubscriptionStore.premiumUntilNotifier.value;
    final now = DateTime.now();
    final isPremium = until != null && until.isAfter(now);
    final remaining = until != null ? until.difference(now) : Duration.zero;

    return ColoredBox(
      color: t.bg1,
      child: RefreshIndicator(
        color: t.accent,
        onRefresh: () => context.read<ContentStore>().refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 100),
          children: [
          const AppHeader(title: 'Akaunti', subtitle: 'AKAUNTI YAKO'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [t.accent, t.accent2]),
                    boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.4), blurRadius: 20)],
                  ),
                  alignment: Alignment.center,
                  child: Text(letters, style: orbitron(28, weight: FontWeight.w900).copyWith(color: Colors.black)),
                ),
                const SizedBox(height: 16),
                Text(
                  displayName,
                  style: orbitron(18).copyWith(color: t.text, letterSpacing: 0.6),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _SubscriptionCard(
              t: t,
              isPremium: isPremium,
              remaining: remaining,
              expiryLabel: until != null ? _formatExpiryDate(until) : '',
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _MenuTile(
                  t: t,
                  g: const [Color(0xFF00e5ff), Color(0xFF7c3aed)],
                  icon: Ionicons.settings_outline,
                  title: 'Settings',
                  subtitle: 'Themes, preferences',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                ),
                const SizedBox(height: 10),
                _MenuTile(
                  t: t,
                  g: const [Color(0xFF00e676), Color(0xFF00bfa5)],
                  icon: Ionicons.share_social_outline,
                  title: 'Share App',
                  subtitle: 'Invite your friends',
                  onTap: () {},
                ),
                const SizedBox(height: 10),
                _MenuTile(
                  t: t,
                  g: const [Color(0xFFff6b6b), Color(0xFFee0979)],
                  icon: Ionicons.call_outline,
                  title: 'Support',
                  subtitle: 'Help & contact',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.t,
    required this.isPremium,
    required this.remaining,
    required this.expiryLabel,
  });

  final AppThemeColors t;
  final bool isPremium;
  final Duration remaining;
  final String expiryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: t.card,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isPremium) ...[
                  Icon(Ionicons.star, size: 18, color: t.premium),
                  const SizedBox(height: 6),
                  Text(
                    'Premium User',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: orbitron(11, weight: FontWeight.w800).copyWith(
                      color: t.premium,
                      height: 1.15,
                    ),
                  ),
                ] else ...[
                  Text(
                    'Free user only',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: orbitron(11, weight: FontWeight.w800).copyWith(
                      color: t.text2,
                      height: 1.15,
                    ),
                  ),
                ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (isPremium) ...[
            Divider(height: 1, thickness: 1, color: t.border),
            Container(
              color: t.card.withValues(alpha: 0.92),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Ionicons.calendar_outline, size: 16, color: t.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Kifurushi chako kitaisha $expiryLabel',
                          style: rajdhani(13, weight: FontWeight.w600).copyWith(color: t.text, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _countdownSwahili(remaining),
                    style: rajdhani(12, weight: FontWeight.w500).copyWith(
                      color: t.text2,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.t,
    required this.g,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final AppThemeColors t;
  final List<Color> g;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: t.border)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: LinearGradient(colors: g)),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: Colors.black),
        ),
        title: Text(title, style: rajdhani(15, weight: FontWeight.w600).copyWith(color: t.text)),
        subtitle: Text(subtitle, style: rajdhani(12).copyWith(color: t.text2)),
        trailing: Text('›', style: TextStyle(color: t.text2, fontSize: 20)),
      ),
    );
  }
}
