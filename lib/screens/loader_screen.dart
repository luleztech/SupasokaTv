import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/theme/brand_palette.dart';
import 'package:supasoka/widgets/internet_required_card.dart';

const _bgDeep = BrandPalette.bgDeep;
const _bgMid = BrandPalette.bgMid;
const _accent = BrandPalette.accent;
const _accentWarm = BrandPalette.accentWarm;
const _white = BrandPalette.white;

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
  late final AnimationController _waveCtrl;

  late final Animation<double> _introSlide;
  late final Animation<double> _introOpacity;
  late final Animation<double> _exitFade;

  bool _bootStarted = false;
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
      duration: const Duration(seconds: 12),
    )..repeat();

    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _introSlide = Tween<double>(begin: 28, end: 0).animate(
      CurvedAnimation(parent: _introCtrl, curve: Curves.easeOutCubic),
    );
    _introOpacity = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.0, 0.75, curve: Curves.easeOut),
    );

    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
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

    if (!await _hasInternetConnection()) {
      if (!mounted) return;
      await _promptUntilOnline();
      if (!mounted) return;
    }

    if (!mounted) return;
    final minSplash = Future<void>.delayed(const Duration(milliseconds: 320));
    final load = context.read<ContentStore>().bootstrapForSplash();

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

    unawaited(_registerUserIdentityAfterHome());

    setState(() => _status = 'Ready');
    await _exitCtrl.forward();
    _goDone();
  }

  Future<void> _registerUserIdentityAfterHome() async {
    try {
      final savedPhone = await UserIdentity.getSavedPhoneNumber();
      final reg = await UserIdentity.registerWithBackend(phone: savedPhone);
      if (reg.premiumUntilMs != null &&
          reg.premiumUntilMs! > DateTime.now().millisecondsSinceEpoch) {
        await SubscriptionStore.setPremiumUntilMs(reg.premiumUntilMs!);
        await SubscriptionStore.refreshNotifierFromPrefs();
      } else if (reg.recovered) {
        await SubscriptionStore.syncPremiumFromBackend(force: true);
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Deferred user registration failed: $e\n$st');
      }
    }
  }

  void _goDone() {
    if (_navigating || !mounted) return;
    _navigating = true;
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) widget.onDone();
    });
  }

  Future<void> _promptUntilOnline() async {
    while (mounted) {
      if (await _hasInternetConnection()) return;
      if (!mounted) return;

      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: _bgDeep.withValues(alpha: 0.94),
        builder: (ctx) => PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: InternetRequiredCard(
              onRetry: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      );
    }
  }

  Future<bool> _hasInternetConnection() async {
    final origin = apiConfigUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (origin.isNotEmpty) {
      try {
        final uri = Uri.parse('$origin/api/v1/public/config-meta').replace(
          queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
        );
        final res = await http.get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
        ).timeout(Duration(seconds: kIsWeb ? 10 : 5));
        if (res.statusCode == 200) return true;
      } catch (_) {}
    }

    if (kIsWeb) {
      if (origin.isEmpty) return true;
      return false;
    }

    try {
      final response = await http
          .head(Uri.parse('https://www.example.com'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _ambientCtrl.dispose();
    _waveCtrl.dispose();
    _introCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: _bgDeep,
      body: FadeTransition(
        opacity: Tween<double>(begin: 1.0, end: 0.0).animate(_exitFade),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: _bgDeep),
            AnimatedBuilder(
              animation: _ambientCtrl,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ArcFieldPainter(t: _ambientCtrl.value),
                  size: size,
                );
              },
            ),
            // Cinematic letterbox
            const Align(
              alignment: Alignment.topCenter,
              child: _LetterboxBar(),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _LetterboxBar(flip: true),
            ),
            // Left signal rail
            AnimatedBuilder(
              animation: _waveCtrl,
              builder: (context, _) {
                return CustomPaint(
                  painter: _SignalRailPainter(progress: _waveCtrl.value),
                  size: size,
                );
              },
            ),
            // Waveform strip
            Positioned(
              left: 0,
              right: 0,
              bottom: pad.bottom + 72,
              height: 56,
              child: AnimatedBuilder(
                animation: _waveCtrl,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _WaveformPainter(t: _waveCtrl.value),
                  );
                },
              ),
            ),
            // Giant watermark
            Positioned(
              right: -18,
              top: size.height * 0.06,
              child: IgnorePointer(
                child: Text(
                  'S',
                  style: orbitron(220, weight: FontWeight.w900).copyWith(
                    color: _white.withValues(alpha: 0.025),
                    height: 0.85,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: AnimatedBuilder(
                animation: Listenable.merge([_introCtrl, _waveCtrl]),
                builder: (context, _) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(flex: 3),
                        Transform.translate(
                          offset: Offset(0, _introSlide.value),
                          child: Opacity(
                            opacity: _introOpacity.value,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _HexLogo(spin: _waveCtrl.value),
                                const SizedBox(width: 22),
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          'SUPA',
                                          maxLines: 1,
                                          softWrap: false,
                                          style: orbitron(38, weight: FontWeight.w900).copyWith(
                                            color: _white,
                                            height: 0.9,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                        ShaderMask(
                                          shaderCallback: (b) => const LinearGradient(
                                            colors: [_accent, _accentWarm],
                                          ).createShader(b),
                                          child: Text(
                                            'SOKA',
                                            maxLines: 1,
                                            softWrap: false,
                                            style: orbitron(38, weight: FontWeight.w900).copyWith(
                                              color: _white,
                                              height: 0.9,
                                              letterSpacing: 2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Transform.translate(
                          offset: Offset(0, _introSlide.value * 0.6),
                          child: Opacity(
                            opacity: _introOpacity.value * 0.8,
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 2,
                                  color: _accentWarm,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'LIVE TV  ·  STREAMS  ·  ANYWHERE',
                                  style: rajdhani(12, weight: FontWeight.w600).copyWith(
                                    color: _white.withValues(alpha: 0.55),
                                    letterSpacing: 2.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(flex: 2),
                        Opacity(
                          opacity: _introOpacity.value,
                          child: _SegmentLoader(tick: _waveCtrl.value),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            _LiveDot(pulse: _waveCtrl.value),
                            const SizedBox(width: 8),
                            Text(
                              _status.toUpperCase(),
                              style: rajdhani(11, weight: FontWeight.w600).copyWith(
                                color: _white.withValues(alpha: 0.4),
                                letterSpacing: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterboxBar extends StatelessWidget {
  const _LetterboxBar({this.flip = false});

  final bool flip;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 28,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: flip ? Alignment.bottomCenter : Alignment.topCenter,
          end: flip ? Alignment.topCenter : Alignment.bottomCenter,
          colors: [
            _bgMid,
            _bgDeep,
          ],
        ),
        border: Border(
          top: flip ? BorderSide.none : BorderSide(color: _white.withValues(alpha: 0.06)),
          bottom: flip ? BorderSide(color: _white.withValues(alpha: 0.06)) : BorderSide.none,
        ),
      ),
    );
  }
}

/// Sweeping arcs from the top-right — asymmetric, not a centered glow.
class _ArcFieldPainter extends CustomPainter {
  const _ArcFieldPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width * 1.05, size.height * -0.08);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 4; i++) {
      final radius = size.width * (0.42 + i * 0.14) + math.sin((t + i * 0.15) * math.pi * 2) * 6;
      stroke
        ..strokeWidth = 1.2 - i * 0.2
        ..color = (i.isEven ? _accent : _accentWarm).withValues(alpha: 0.07 + i * 0.02);
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: radius),
        math.pi * 0.55,
        math.pi * 0.55,
        false,
        stroke,
      );
    }

    // Diagonal amber slash
    final slash = Path()
      ..moveTo(size.width * 0.62, 0)
      ..lineTo(size.width, size.height * 0.22);
    canvas.drawPath(
      slash,
      Paint()
        ..color = _accentWarm.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcFieldPainter old) => old.t != t;
}

/// Vertical rail with a traveling pulse dot.
class _SignalRailPainter extends CustomPainter {
  const _SignalRailPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const x = 18.0;
    final rail = Paint()
      ..color = _white.withValues(alpha: 0.08)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, size.height * 0.18), Offset(x, size.height * 0.82), rail);

    final dotY = size.height * (0.18 + progress * 0.64);
    canvas.drawCircle(Offset(x, dotY), 4, Paint()..color = _accent);
    canvas.drawCircle(
      Offset(x, dotY),
      10,
      Paint()..color = _accent.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(covariant _SignalRailPainter old) => old.progress != progress;
}

/// Audio-style waveform along the bottom.
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 48;
    final barW = size.width / bars;
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (var i = 0; i < bars; i++) {
      final phase = (i / bars + t) * math.pi * 4;
      final h = 6 + (math.sin(phase) * 0.5 + 0.5) * 38;
      final x = i * barW + barW * 0.3;
      final isPeak = math.sin(phase) > 0.7;
      paint
        ..strokeWidth = barW * 0.45
        ..color = isPeak
            ? _accentWarm.withValues(alpha: 0.55)
            : _accent.withValues(alpha: 0.22);
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => old.t != t;
}

class _HexLogo extends StatelessWidget {
  const _HexLogo({required this.spin});

  final double spin;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: spin * math.pi * 2,
            child: CustomPaint(
              size: const Size(76, 76),
              painter: _HexBorderPainter(),
            ),
          ),
          ClipPath(
            clipper: _HexClipper(),
            child: Container(
              width: 58,
              height: 58,
              color: _bgMid,
              alignment: Alignment.center,
              child: Icon(
                Icons.play_arrow_rounded,
                size: 30,
                color: _accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HexClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => _hexPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

Path _hexPath(Size size) {
  final w = size.width;
  final h = size.height;
  final path = Path();
  path.moveTo(w * 0.5, 0);
  path.lineTo(w, h * 0.25);
  path.lineTo(w, h * 0.75);
  path.lineTo(w * 0.5, h);
  path.lineTo(0, h * 0.75);
  path.lineTo(0, h * 0.25);
  path.close();
  return path;
}

class _HexBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _hexPath(size),
      Paint()
        ..color = _accent.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SegmentLoader extends StatelessWidget {
  const _SegmentLoader({required this.tick});

  final double tick;

  @override
  Widget build(BuildContext context) {
    const segments = 10;
    final active = (tick * segments).floor() % segments;

    return Row(
      children: List.generate(segments, (i) {
        final lit = i <= active;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < segments - 1 ? 5 : 0),
            height: 3,
            decoration: BoxDecoration(
              color: lit
                  ? (i.isEven ? _accent : _accentWarm)
                  : _white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      }),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.pulse});

  final double pulse;

  @override
  Widget build(BuildContext context) {
    final scale = 0.7 + pulse * 0.3;
    return Container(
      width: 8 * scale,
      height: 8 * scale,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _accentWarm,
        boxShadow: [
          BoxShadow(
            color: _accentWarm.withValues(alpha: 0.5),
            blurRadius: 8,
          ),
        ],
      ),
    );
  }
}
