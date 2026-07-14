import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';

/// Cinematic multi-layer background with ambient glows (Netflix-tier depth).
class PremiumAmbientBackground extends StatelessWidget {
  const PremiumAmbientBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF050505), Color(0xFF0B0B0B), Color(0xFF050505)],
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -80,
          child: _glow(280, const Color(0x1FFF3B30)),
        ),
        Positioned(
          top: 80,
          right: -100,
          child: _glow(240, const Color(0x14FFD700)),
        ),
        Positioned(
          bottom: 40,
          left: -60,
          child: _glow(200, const Color(0x14FF6B00)),
        ),
        ?child,
      ],
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}

/// Frosted glass panel — blur + subtle border.
class PremiumGlassPanel extends StatelessWidget {
  const PremiumGlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.blur = 14,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            color: const Color(0xFF111111).withValues(alpha: 0.72),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Pulsing LIVE badge with red glow.
class PremiumLiveBadge extends StatefulWidget {
  const PremiumLiveBadge({
    super.key,
    this.compact = false,
    this.label = 'LIVE',
  });

  final bool compact;
  final String label;

  @override
  State<PremiumLiveBadge> createState() => _PremiumLiveBadgeState();
}

class _PremiumLiveBadgeState extends State<PremiumLiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padH = widget.compact ? 6.0 : 8.0;
    final padV = widget.compact ? 3.0 : 4.0;
    final fs = widget.compact ? 7.0 : 8.0;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = 0.35 + _pulse.value * 0.35;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF3B30), Color(0xFFCC1F1A)],
            ),
            borderRadius: BorderRadius.circular(widget.compact ? 6 : 8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF3B30).withValues(alpha: glow),
                blurRadius: widget.compact ? 10 : 14,
                spreadRadius: -2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(animation: _pulse),
          SizedBox(width: widget.compact ? 4 : 6),
          Text(
            widget.label.toUpperCase(),
            style: orbitron(fs, weight: FontWeight.w900).copyWith(
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatelessWidget {
  const _PulsingDot({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final s = 0.75 + animation.value * 0.35;
        return Transform.scale(
          scale: s,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.6 + animation.value * 0.3),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Premium CTA chip (carousel / hero).
class PremiumWatchChip extends StatelessWidget {
  const PremiumWatchChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF3B30), Color(0xFFFF6B00)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF3B30).withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        'ANGALIA SASA',
        style: orbitron(9, weight: FontWeight.w900).copyWith(
          color: Colors.white,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// Active category gradient (red → orange).
LinearGradient get premiumActivePillGradient => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFF3B30), Color(0xFFFF6B00)],
    );

Color premiumBorder(AppThemeColors t) => Colors.white.withValues(alpha: 0.08);
