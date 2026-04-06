import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Cinematic admin launch animation. Calls [onFinished] when the sequence completes.
class AdminSplashScreen extends StatefulWidget {
  const AdminSplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<AdminSplashScreen> createState() => _AdminSplashScreenState();
}

class _AdminSplashScreenState extends State<AdminSplashScreen> with TickerProviderStateMixin {
  late final AnimationController _master;

  late final Animation<double> _mesh;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _glowPulse;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _subtitleOpacity;
  late final Animation<double> _barShimmer;
  late final Animation<double> _orbit;
  late final Animation<double> _shieldRotate;

  @override
  void initState() {
    super.initState();
    _master = AnimationController(vsync: this, duration: const Duration(milliseconds: 2900));

    _mesh = CurvedAnimation(parent: _master, curve: Curves.easeInOut);
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.05, 0.5, curve: Curves.easeOutCubic)),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.05, 0.35, curve: Curves.easeOut)),
    );
    _glowPulse = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.1, 0.55, curve: Curves.easeOut)),
    );
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.35, 0.65, curve: Curves.easeOut)),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.35, 0.7, curve: Curves.easeOutCubic)),
    );
    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.5, 0.78, curve: Curves.easeOut)),
    );
    _barShimmer = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.45, 0.95, curve: Curves.easeOutCubic)),
    );
    _orbit = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.0, 1.0, curve: Curves.linear)),
    );
    _shieldRotate = Tween<double>(begin: -0.12, end: 0.0).animate(
      CurvedAnimation(parent: _master, curve: const Interval(0.05, 0.55, curve: Curves.easeOutBack)),
    );

    _master.forward().then((_) {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _master.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return AnimatedBuilder(
      animation: _master,
      builder: (context, _) {
        final meshT = _mesh.value;
        final a1 = Alignment(-0.8 + meshT * 0.4, -1.0 + meshT * 0.2);
        final a2 = Alignment(0.9 - meshT * 0.3, 1.0 - meshT * 0.15);
        final orbit = _orbit.value;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: a1,
              end: a2,
              colors: const [
                Color(0xFF03040a),
                Color(0xFF0c1020),
                Color(0xFF151528),
                Color(0xFF0a1628),
              ],
              stops: const [0.0, 0.35, 0.7, 1.0],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _GridGlowPainter(progress: meshT),
              ),
              ...List.generate(16, (i) {
                final angle = (i / 16) * math.pi * 2 + orbit * math.pi * 1.5;
                final r = size.shortestSide * 0.36;
                final left = size.width / 2 + math.cos(angle) * r - 2;
                final top = size.height / 2 + math.sin(angle) * r - 2;
                return Positioned(
                  left: left,
                  top: top,
                  child: Opacity(
                    opacity: (0.12 + 0.22 * math.sin(orbit * math.pi * 2 + i * 0.4)).clamp(0.0, 1.0),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF8b5cf6).withValues(alpha: 0.75),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 8,
                            color: const Color(0xFF22d3ee).withValues(alpha: 0.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.rotate(
                              angle: orbit * math.pi * 2 * 0.25,
                              child: Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    width: 2,
                                    color: Color.lerp(
                                      const Color(0xFF6366f1).withValues(alpha: 0.2),
                                      const Color(0xFF6366f1).withValues(alpha: 0.5),
                                      _glowPulse.value,
                                    )!,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF6366f1).withValues(alpha: 0.12 + 0.1 * _glowPulse.value),
                                      blurRadius: 40,
                                      spreadRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Transform.rotate(
                              angle: -orbit * math.pi * 2 * 0.18,
                              child: Container(
                                width: 130,
                                height: 130,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    width: 1.5,
                                    color: const Color(0xFF06b6d4).withValues(alpha: 0.22),
                                  ),
                                ),
                              ),
                            ),
                            Transform.rotate(
                              angle: _shieldRotate.value,
                              child: Transform.scale(
                                scale: _logoScale.value,
                                child: Opacity(
                                  opacity: _logoOpacity.value,
                                  child: Container(
                                    padding: const EdgeInsets.all(26),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          const Color(0xFF8b5cf6).withValues(alpha: 0.55 * _glowPulse.value),
                                          const Color(0xFF06b6d4).withValues(alpha: 0.25),
                                          Colors.transparent,
                                        ],
                                        stops: const [0.0, 0.55, 1.0],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF8b5cf6).withValues(alpha: 0.45 * _glowPulse.value),
                                          blurRadius: 36,
                                          spreadRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.admin_panel_settings_rounded,
                                      size: 56,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SlideTransition(
                        position: _titleSlide,
                        child: FadeTransition(
                          opacity: _titleOpacity,
                          child: ShaderMask(
                            shaderCallback: (bounds) {
                              return const LinearGradient(
                                colors: [
                                  Color(0xFFe9d5ff),
                                  Color(0xFFa78bfa),
                                  Color(0xFF22d3ee),
                                ],
                              ).createShader(bounds);
                            },
                            child: const Text(
                              'SUPAADMIN',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 6,
                                color: Colors.white,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FadeTransition(
                        opacity: _subtitleOpacity,
                        child: Text(
                          'Supasoka · Administrator',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            fontSize: 13,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),
                      SizedBox(
                        width: 200,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            minHeight: 5,
                            value: _barShimmer.value,
                            backgroundColor: Colors.white.withValues(alpha: 0.06),
                            color: const Color(0xFF8b5cf6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GridGlowPainter extends CustomPainter {
  _GridGlowPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final step = 48.0;
    final offset = progress * 24;
    for (double x = -offset; x < size.width + step; x += step) {
      paint.color = const Color(0xFF6366f1).withValues(alpha: 0.04 + 0.03 * math.sin(progress * math.pi));
      canvas.drawLine(Offset(x, 0), Offset(x + 40, size.height), paint);
    }
    for (double y = -offset; y < size.height + step; y += step) {
      paint.color = const Color(0xFF06b6d4).withValues(alpha: 0.035);
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 30), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridGlowPainter oldDelegate) => oldDelegate.progress != progress;
}
