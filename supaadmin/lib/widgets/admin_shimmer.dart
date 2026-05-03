import 'package:flutter/material.dart';

/// Moving highlight shimmer — use for skeleton rows, cards, or any placeholder.
class AdminShimmer extends StatefulWidget {
  const AdminShimmer({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFF141824),
    this.highlightColor = const Color(0xFF2d3548),
  });

  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  @override
  State<AdminShimmer> createState() => _AdminShimmerState();
}

class _AdminShimmerState extends State<AdminShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final dx = 2.0 * t - 1.0;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(dx - 1.2, 0),
              end: Alignment(dx + 1.2, 0),
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.25, 0.5, 0.75],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Rounded rectangle placeholder with shimmer (common for list tiles).
class AdminShimmerBox extends StatelessWidget {
  const AdminShimmerBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return AdminShimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF141824),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// Full-screen admin loading: logo + shimmer skeleton (storage slow after splash).
class AdminShimmerLoadingPage extends StatelessWidget {
  const AdminShimmerLoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF07080c),
            Color(0xFF0f1219),
            Color(0xFF12151f),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AdminShimmer(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFF141824),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AdminShimmerBox(width: 160, height: 16, borderRadius: 8),
                        const SizedBox(height: 10),
                        AdminShimmerBox(width: 220, height: 12, borderRadius: 6),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              AdminShimmerBox(height: 120, borderRadius: 18),
              const SizedBox(height: 16),
              AdminShimmerBox(height: 14, borderRadius: 6),
              const SizedBox(height: 10),
              AdminShimmerBox(width: 200, height: 14, borderRadius: 6),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 5,
                  separatorBuilder: (context, _) => const SizedBox(height: 12),
                  itemBuilder: (context, _) => Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Row(
                      children: [
                        AdminShimmer(
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF141824),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AdminShimmerBox(height: 14, borderRadius: 6),
                              const SizedBox(height: 8),
                              AdminShimmerBox(width: 120, height: 10, borderRadius: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Loading configuration…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.primary.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Run [future] while showing a small shimmer dialog (import/save heavy work).
Future<T?> adminWithShimmerDialog<T>(
  BuildContext context, {
  required Future<T> future,
  String message = 'Please wait…',
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: const Color(0xFF1a1e2a),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 200,
                height: 8,
                child: AdminShimmer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF141824),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await future;
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
