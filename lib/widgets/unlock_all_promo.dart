import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/theme/brand_palette.dart';

/// Home CTA — opens the unlock / payment tab.
class UnlockAllPromoCard extends StatefulWidget {
  const UnlockAllPromoCard({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<UnlockAllPromoCard> createState() => _UnlockAllPromoCardState();
}

class _UnlockAllPromoCardState extends State<UnlockAllPromoCard> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.98),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: BrandPalette.activeGradient,
            boxShadow: [
              BoxShadow(
                color: BrandPalette.accent.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: BrandPalette.accentWarm.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(1.5),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  BrandPalette.bgMid,
                  BrandPalette.bgDeep.withValues(alpha: 0.96),
                  BrandPalette.bgMid.withValues(alpha: 0.92),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20.5),
              child: Stack(
                children: [
                  Positioned(
                    top: -28,
                    right: -18,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            BrandPalette.accent.withValues(alpha: 0.22),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -20,
                    left: -10,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            BrandPalette.accentWarm.withValues(alpha: 0.12),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 14,
                    bottom: 14,
                    width: 3,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(gradient: BrandPalette.activeGradient),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: BrandPalette.activeGradient,
                            boxShadow: [
                              BoxShadow(
                                color: BrandPalette.accentWarm.withValues(alpha: 0.4),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                Ionicons.wallet_outline,
                                size: 22,
                                color: BrandPalette.white.withValues(alpha: 0.95),
                              ),
                              Positioned(
                                bottom: 9,
                                right: 9,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: BrandPalette.bgDeep,
                                    border: Border.all(color: BrandPalette.white, width: 1.5),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Ionicons.add,
                                    size: 8,
                                    color: BrandPalette.accentWarm,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShaderMask(
                                shaderCallback: (b) => BrandPalette.activeGradient.createShader(b),
                                child: Text(
                                  'Jinsi Ya Kulipia',
                                  style: inter(16, weight: FontWeight.w800).copyWith(
                                    color: BrandPalette.white,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Njia salama za kufungua chaneli zote',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: rajdhani(11, weight: FontWeight.w600).copyWith(
                                  color: BrandPalette.white.withValues(alpha: 0.52),
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: BrandPalette.white.withValues(alpha: 0.08),
                            border: Border.all(color: BrandPalette.accent.withValues(alpha: 0.35)),
                          ),
                          child: const Icon(
                            Ionicons.arrow_forward,
                            size: 18,
                            color: BrandPalette.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
