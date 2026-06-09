import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';

/// Home promo card below free channels — unlock all with discount CTA.
class UnlockAllPromoCard extends StatelessWidget {
  const UnlockAllPromoCard({super.key, required this.onPressed});

  final VoidCallback onPressed;

  String? _originalPriceLabel(ContentStore store) {
    final packages = store.premiumPackages;
    if (packages.isEmpty) return null;
    final popular = packages.where((p) => p.popular);
    final pick = popular.isNotEmpty ? popular.first : packages.first;
    final price = pick.price.trim();
    if (price.isEmpty) return null;
    if (price.toLowerCase().startsWith('tsh') || price.contains('/')) return price;
    return 'Tsh $price/=';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final store = context.watch<ContentStore>();
    final originalPrice = _originalPriceLabel(store);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              t.accent.withValues(alpha: 0.22),
              const Color(0xFF14141a),
              t.bg2.withValues(alpha: 0.95),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
          border: Border.all(color: t.accent.withValues(alpha: 0.45), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: t.glow.withValues(alpha: 0.28),
              blurRadius: 28,
              spreadRadius: -8,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              Positioned(
                top: -36,
                right: -24,
                child: Icon(
                  Ionicons.sparkles,
                  size: 120,
                  color: t.accent.withValues(alpha: 0.07),
                ),
              ),
              Positioned(
                bottom: -28,
                left: -18,
                child: Icon(
                  Ionicons.key,
                  size: 96,
                  color: t.gold.withValues(alpha: 0.06),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              colors: [t.gold, t.gold.withValues(alpha: 0.78)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: t.gold.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Text(
                            'PRO',
                            style: orbitron(9, weight: FontWeight.w900).copyWith(
                              color: Colors.black,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ofa maalum',
                            style: rajdhani(11, weight: FontWeight.w700).copyWith(
                              color: t.text2.withValues(alpha: 0.9),
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        Icon(Ionicons.lock_open_outline, size: 18, color: t.accent2.withValues(alpha: 0.9)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text.rich(
                      TextSpan(
                        style: rajdhani(16, weight: FontWeight.w700).copyWith(
                          color: t.text,
                          height: 1.35,
                        ),
                        children: [
                          const TextSpan(text: 'Fungua Chaneli zote kwa '),
                          if (originalPrice != null) ...[
                            TextSpan(
                              text: '$originalPrice ',
                              style: TextStyle(
                                color: t.text2.withValues(alpha: 0.75),
                                decoration: TextDecoration.lineThrough,
                                decorationColor: t.text2.withValues(alpha: 0.55),
                                decorationThickness: 2,
                              ),
                            ),
                          ],
                          const TextSpan(text: 'bei punguzo hadi '),
                          TextSpan(
                            text: '60%',
                            style: TextStyle(
                              color: t.accent2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _UnlockCtaButton(onPressed: onPressed, colors: t),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnlockCtaButton extends StatefulWidget {
  const _UnlockCtaButton({required this.onPressed, required this.colors});

  final VoidCallback onPressed;
  final AppThemeColors colors;

  @override
  State<_UnlockCtaButton> createState() => _UnlockCtaButtonState();
}

class _UnlockCtaButtonState extends State<_UnlockCtaButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.colors;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = 0.28 + _pulse.value * 0.18;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [t.accent, t.accent2],
            ),
            boxShadow: [
              BoxShadow(
                color: t.glow.withValues(alpha: glow),
                blurRadius: 20,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onPressed,
              splashColor: Colors.white.withValues(alpha: 0.16),
              highlightColor: Colors.white.withValues(alpha: 0.08),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Ionicons.flash, size: 20, color: Colors.white.withValues(alpha: 0.96)),
                    const SizedBox(width: 10),
                    Text(
                      'Fungua zote sasa',
                      style: inter(15, weight: FontWeight.w800).copyWith(
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Ionicons.chevron_forward, size: 18, color: Colors.white.withValues(alpha: 0.9)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: const SizedBox.shrink(),
    );
  }
}
