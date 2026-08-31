import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/theme/brand_palette.dart';

/// Fast cold-start splash — same backend bootstrap as the mobile app, no carousel/tabs.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onReady});

  final VoidCallback onReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  String _status = kLoadingMessages.first;
  Timer? _msgTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    var msgIdx = 0;
    _msgTimer = Timer.periodic(const Duration(milliseconds: 520), (_) {
      if (!mounted) return;
      msgIdx = (msgIdx + 1) % kLoadingMessages.length;
      setState(() => _status = kLoadingMessages[msgIdx]);
    });

    final store = context.read<ContentStore>();
    await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 480)),
      store.bootstrap(),
    ]);

    _msgTimer?.cancel();
    if (!mounted) return;
    widget.onReady();
  }

  @override
  void dispose() {
    _msgTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = 0.85 + _pulse.value * 0.15;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: BrandPalette.surfaceGradient,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.scale(
                scale: t,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: BrandPalette.activeGradient,
                    boxShadow: [
                      BoxShadow(
                        color: BrandPalette.accent.withValues(alpha: 0.35),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'TV',
                    style: TextStyle(
                      color: BrandPalette.bgDeep,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'SupaTV',
                style: TextStyle(
                  color: BrandPalette.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: BrandPalette.white.withValues(alpha: 0.65),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: math.min(MediaQuery.sizeOf(context).width * 0.5, 220),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.white12,
                  color: BrandPalette.accent,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
