import 'package:flutter/material.dart';

/// One-shot fade + slide-up for dashboard tiles and rows.
class StaggerEntrance extends StatelessWidget {
  const StaggerEntrance({
    super.key,
    required this.index,
    required this.child,
    this.durationMs = 420,
    this.slide = 20,
  });

  final int index;
  final Widget child;
  final int durationMs;
  final double slide;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: durationMs + index * 55),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, slide * (1 - t)),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}
