import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/widgets/app_header.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Future<void> _share() async {
    await Share.share('Watch live football, movies & more on Supasoka! Download now.', subject: 'Supasoka');
  }

  static Future<void> _openWhatsapp(BuildContext context) async {
    final d = context.read<ContentStore>().customerCareWhatsapp.replaceAll(RegExp(r'\D'), '');
    if (d.length < 8) return;
    final u = Uri.parse('https://wa.me/$d');
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  static void _openKuhusu(BuildContext context) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (context, animation, secondaryAnimation) => const _KuhusuSupasokaScreen(),
        transitionsBuilder: (context, anim, secondaryAnimation, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<ThemeController>();
    final t = tc.colors;
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: t.bg1,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, top + 10, 24, 0),
              child: Row(
                children: [
                  BackBtn(onPress: () => Navigator.of(context).pop()),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (b) => LinearGradient(colors: [t.accent, t.accent2]).createShader(b),
                          child: Text('Settings', style: orbitron(22, weight: FontWeight.w900).copyWith(color: Colors.white)),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              width: 14,
                              height: 2,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [t.accent, t.accent2]),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text('PREFERENCES', style: rajdhani(11, weight: FontWeight.w600).copyWith(color: t.text2, letterSpacing: 3)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: Divider(height: 24, color: t.border.withValues(alpha: 0.4), indent: 24, endIndent: 24)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _sectionTitle(t, Ionicons.color_palette_outline, 'THEME'),
                _themeRow(context, tc),
                const SizedBox(height: 24),
                _sectionTitle(t, Ionicons.information_circle_outline, 'APP INFO'),
                _group(
                  t,
                  [
                    _row(t, Ionicons.phone_portrait_outline, 'App Name', 'Supasoka'),
                    _row(t, Ionicons.pricetag_outline, 'Version', '1.1.0'),
                  ],
                ),
                const SizedBox(height: 24),
                _sectionTitle(t, Ionicons.flash_outline, 'ACTIONS'),
                _group(
                  t,
                  [
                    _row(t, Ionicons.share_social_outline, 'Share App', 'Invite Friends', onTap: _share),
                    _row(t, Ionicons.star_outline, 'Rate App', 'Play Store'),
                    _row(
                      t,
                      Ionicons.heart_outline,
                      'Kuhusu Supasoka',
                      'Soma',
                      onTap: () => _openKuhusu(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _sectionTitle(t, Ionicons.help_circle_outline, 'HELP'),
                _group(
                  t,
                  [
                    _row(t, Ionicons.logo_whatsapp, 'WhatsApp Support', 'Chat Now', onTap: () => _openWhatsapp(context)),
                    _row(t, Ionicons.mail_outline, 'Email Support', 'ghettodevelopers@gmail.com'),
                  ],
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(AppThemeColors t, IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 14, color: t.accent),
          const SizedBox(width: 8),
          Text(title, style: orbitron(13).copyWith(color: t.text, letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _themeRow(BuildContext context, ThemeController tc) {
    final t = tc.colors;
    const dots = [
      _Dot(ThemeKey.dark, [Color(0xFF1a0508), Color(0xFFe8002d)]),
      _Dot(ThemeKey.neon, [Color(0xFFff00ff), Color(0xFF00ffaa)]),
      _Dot(ThemeKey.gold, [Color(0xFFffd700), Color(0xFFff8c00)]),
      _Dot(ThemeKey.crimson, [Color(0xFFe8002d), Color(0xFFff6b6b)]),
    ];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: t.surface.withValues(alpha: 0.65),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: t.bg1,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.border),
            ),
            child: Icon(Ionicons.color_palette_outline, size: 15, color: t.accent),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('App Theme', style: rajdhani(14, weight: FontWeight.w600).copyWith(color: t.text))),
          Row(
            children: [
              for (final d in dots)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      tc.setTheme(d.key);
                    },
                    child: Transform.scale(
                      scale: tc.themeKey == d.key ? 1.15 : 1.0,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: d.colors),
                          border: tc.themeKey == d.key ? Border.all(color: Colors.white, width: 2) : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _group(AppThemeColors t, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: t.card.withValues(alpha: 0.85),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: _joinDividers(t, children)),
    );
  }

  List<Widget> _joinDividers(AppThemeColors t, List<Widget> children) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      out.add(children[i]);
      if (i < children.length - 1) out.add(Divider(height: 1, color: t.border));
    }
    return out;
  }

  Widget _row(AppThemeColors t, IconData icon, String label, String value, {VoidCallback? onTap}) {
    return Material(
      color: t.card,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: t.bg1,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.border),
                ),
                child: Icon(icon, size: 15, color: t.accent),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: rajdhani(14, weight: FontWeight.w600).copyWith(color: t.text))),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: rajdhani(13).copyWith(color: t.text2),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot {
  const _Dot(this.key, this.colors);

  final ThemeKey key;
  final List<Color> colors;
}

class _KuhusuSupasokaScreen extends StatefulWidget {
  const _KuhusuSupasokaScreen();

  @override
  State<_KuhusuSupasokaScreen> createState() => _KuhusuSupasokaScreenState();
}

class _KuhusuSupasokaScreenState extends State<_KuhusuSupasokaScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Animation<double> _interval(double begin, double end) {
    return Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _c,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;

    return Scaffold(
      backgroundColor: t.bg1,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [t.bg1, t.bg2, t.bg1.withValues(alpha: 0.95)],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 16, 8),
                  child: Row(
                    children: [
                      BackBtn(onPress: () => Navigator.of(context).pop()),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FadeTransition(
                          opacity: _interval(0.0, 0.25),
                          child: ShaderMask(
                            shaderCallback: (b) => LinearGradient(colors: [t.accent, t.accent2]).createShader(b),
                            child: Text(
                              'Kuhusu Supasoka',
                              style: orbitron(20, weight: FontWeight.w900).copyWith(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _interval(0.08, 0.35),
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(_interval(0.08, 0.35)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [t.accent, t.accent2]),
                            boxShadow: [
                              BoxShadow(color: t.accent.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 12)),
                            ],
                          ),
                          child: const Icon(Ionicons.tv_outline, color: Colors.white, size: 40),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              SliverToBoxAdapter(
                child: _KuhusuAnimatedBlock(
                  animation: _interval(0.18, 0.48),
                  child: _kuhusuParagraph(
                    t,
                    'Supasoka ni programu ya simu inayokuwezesha kutazama vipindi vya televisheni moja kwa moja kwenye kifaa chako — popote ulipo, kwa urahisi na kwa gharama nafuu kabisa.',
                  ),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: 18)),
              SliverToBoxAdapter(
                child: _KuhusuAnimatedBlock(
                  animation: _interval(0.32, 0.62),
                  child: _kuhusuParagraph(
                    t,
                    'Tunakuletea burudani ya uhakika: michezo, filamu, habari na mengi zaidi, yote yaliyounganishwa kwa uzoefu mwepesi wa kutumia.',
                  ),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: 18)),
              SliverToBoxAdapter(
                child: _KuhusuAnimatedBlock(
                  animation: _interval(0.46, 0.76),
                  child: _kuhusuParagraph(
                    t,
                    'Asante kwa kuchagua Supasoka. Furahia TV ya kisasa mikononi mwako — ubora unaofaa, bei inayolingana na wewe.',
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _interval(0.62, 0.95),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.border),
                        color: t.card,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Ionicons.heart, size: 16, color: t.accent),
                          const SizedBox(width: 8),
                          Text(
                            'Supasoka — TV yako, popote',
                            style: rajdhani(13, weight: FontWeight.w700).copyWith(color: t.text2, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kuhusuParagraph(AppThemeColors t, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: rajdhani(16, weight: FontWeight.w500).copyWith(
          color: t.text,
          height: 1.65,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _KuhusuAnimatedBlock extends StatelessWidget {
  const _KuhusuAnimatedBlock({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(animation);
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(position: slide, child: child),
    );
  }
}
