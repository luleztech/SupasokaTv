import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/theme/app_typography.dart';

const _splashAccent = Color(0xFFFF4F4F);
const _splashAccentSoft = Color(0xFFFF7A7A);
const _splashBgTop = Color(0xFF06060A);
const _splashBgBottom = Color(0xFF0E0E14);

/// Cold-start splash: ambient motion, brand mark, syncs exit with [ContentStore.bootstrap].
class LoaderScreen extends StatefulWidget {
  const LoaderScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<LoaderScreen> createState() => _LoaderScreenState();
}

class _LoaderScreenState extends State<LoaderScreen> with TickerProviderStateMixin {
  late final AnimationController _ambientCtrl;
  late final AnimationController _introCtrl;
  late final AnimationController _exitCtrl;
  late final AnimationController _shimmerCtrl;

  late final Animation<double> _introScale;
  late final Animation<double> _introOpacity;
  late final Animation<double> _exitFade;

  bool _bootStarted = false;
  bool _offline = false;
  bool _navigating = false;
  String _status = '';

  final List<String> _messages = [
    'Connecting…',
    'Loading channels…',
    'Almost there…',
  ];

  @override
  void initState() {
    super.initState();

    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _introScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _introCtrl, curve: Curves.easeOutBack),
    );
    _introOpacity = CurvedAnimation(parent: _introCtrl, curve: const Interval(0.0, 0.65, curve: Curves.easeOut));

    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _exitFade = CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn);

    WidgetsBinding.instance.addPostFrameCallback((_) => _runBoot());
  }

  Future<void> _runBoot() async {
    if (_bootStarted) return;
    _bootStarted = true;
    if (!mounted) return;

    setState(() => _status = _messages.first);
    unawaited(_introCtrl.forward());

    final online = await _hasInternetConnection();
    if (!mounted) return;
    if (!online) {
      setState(() {
        _offline = true;
        _status = 'No connection';
      });
      _bootStarted = false;
      return;
    }

    final minSplash = Future<void>.delayed(const Duration(milliseconds: 1500));
    final load = context.read<ContentStore>().bootstrap();

    var msgIdx = 0;
    final ticker = Timer.periodic(const Duration(milliseconds: 480), (t) {
      if (!mounted) return;
      msgIdx = (msgIdx + 1) % _messages.length;
      setState(() => _status = _messages[msgIdx]);
    });

    try {
      await Future.wait([minSplash, load]);
    } finally {
      ticker.cancel();
    }

    if (!mounted) return;

    final savedPhone = await UserIdentity.getSavedPhoneNumber();
    await UserIdentity.registerWithBackend(phone: savedPhone);
    if (!mounted) return;

    setState(() => _status = 'Ready');
    await _exitCtrl.forward();
    _goDone();
  }

  void _goDone() {
    if (_navigating || !mounted) return;
    _navigating = true;
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) widget.onDone();
    });
  }

  Future<bool> _hasInternetConnection() async {
    if (kIsWeb) {
      // `dart:http` to arbitrary hosts from `localhost` is blocked by browser CORS.
      // A HEAD to example.com always fails on web → falsely showed "No internet".
      // Proceed to [ContentStore.bootstrap]; load errors surface in-app if the API is unreachable.
      return true;
    }
    try {
      final response = await http
          .head(Uri.parse('https://www.example.com'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _ambientCtrl.dispose();
    _shimmerCtrl.dispose();
    _introCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_offline) {
      return Scaffold(
        backgroundColor: _splashBgTop,
        body: _OfflineCard(onRetry: () {
          setState(() {
            _offline = false;
            _status = '';
          });
          _bootStarted = false;
          _runBoot();
        }),
      );
    }

    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: _splashBgTop,
      body: FadeTransition(
        opacity: Tween<double>(begin: 1.0, end: 0.0).animate(_exitFade),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _ambientCtrl,
              builder: (context, _) {
                final t = _ambientCtrl.value * math.pi * 2;
                final dx = math.cos(t * 0.7) * 0.15;
                final dy = math.sin(t * 0.5) * 0.12;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-0.8 + dx, -1.0 + dy),
                      end: Alignment(0.9 - dx, 1.2 + dy),
                      colors: [
                        _splashBgTop,
                        const Color(0xFF12080C),
                        _splashBgBottom,
                      ],
                      stops: const [0.0, 0.48, 1.0],
                    ),
                  ),
                );
              },
            ),
            // Soft bloom
            Positioned(
              top: size.height * 0.12,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _ambientCtrl,
                  builder: (context, _) {
                    final pulse = 0.55 + 0.45 * math.sin(_ambientCtrl.value * math.pi * 2);
                    return Center(
                      child: Container(
                        width: size.width * 0.95,
                        height: size.height * 0.42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _splashAccent.withValues(alpha: 0.08 * pulse),
                              blurRadius: 120,
                              spreadRadius: 20,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // Top vignette
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_introCtrl, _shimmerCtrl]),
                  builder: (context, _) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.scale(
                          scale: _introScale.value,
                          child: Opacity(
                            opacity: _introOpacity.value,
                            child: _BrandMark(shimmer: _shimmerCtrl.value),
                          ),
                        ),
                        const SizedBox(height: 36),
                        Opacity(
                          opacity: _introOpacity.value,
                          child: ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [_splashAccentSoft, _splashAccent, Color(0xFFB71C1C)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: Text(
                              'SUPASOKA',
                              style: orbitron(26, weight: FontWeight.w900).copyWith(
                                color: Colors.white,
                                letterSpacing: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Opacity(
                          opacity: _introOpacity.value * 0.85,
                          child: Text(
                            'Live TV  ·  Streams  ·  Anywhere',
                            style: rajdhani(12, weight: FontWeight.w600).copyWith(
                              color: Colors.white54,
                              letterSpacing: 2.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),
                        SizedBox(
                          width: math.min(size.width * 0.72, 320),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Colors.white.withValues(alpha: 0.06),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _splashAccent.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _status,
                          style: rajdhani(12, weight: FontWeight.w500).copyWith(
                            color: Colors.white38,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glass tile + play glyph — reads fast at any size.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.shimmer});

  final double shimmer;

  @override
  Widget build(BuildContext context) {
    final gloss = shimmer % 1.0;
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _splashAccent.withValues(alpha: 0.35),
        ),
        gradient: LinearGradient(
          begin: Alignment(-1 + gloss * 2, -1),
          end: Alignment(1 - gloss * 2, 1),
          colors: [
            const Color(0xFF2A1818).withValues(alpha: 0.95),
            const Color(0xFF140A0A),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _splashAccent.withValues(alpha: 0.18),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
              ),
            ),
            child: Icon(
              Icons.play_arrow_rounded,
              size: 52,
              color: _splashAccent.withValues(alpha: 0.95),
              shadows: [
                Shadow(
                  color: _splashAccent.withValues(alpha: 0.45),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineCard extends StatelessWidget {
  const _OfflineCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: _splashBgTop),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _splashAccent.withValues(alpha: 0.22),
                ),
                color: const Color(0xFF101018),
                boxShadow: [
                  BoxShadow(
                    color: _splashAccent.withValues(alpha: 0.12),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          _splashAccent.withValues(alpha: 0.35),
                          _splashAccent.withValues(alpha: 0.12),
                        ],
                      ),
                    ),
                    child: const Icon(Ionicons.cloud_offline_outline, size: 34, color: Colors.white),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Hakuna muunganiko wa internet',
                    textAlign: TextAlign.center,
                    style: orbitron(18, weight: FontWeight.w800).copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Mpendwa mteja hakuna muunganiko wa internet hakikisha umewasha data katika simu yako na una MB.',
                    textAlign: TextAlign.center,
                    style: rajdhani(14).copyWith(color: Colors.white70, height: 1.45),
                  ),
                  const SizedBox(height: 26),
                  FilledButton(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: _splashAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Retry', style: rajdhani(15, weight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
