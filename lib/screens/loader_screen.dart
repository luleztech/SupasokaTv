import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/theme/app_typography.dart';

class LoaderScreen extends StatefulWidget {
  const LoaderScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<LoaderScreen> createState() => _LoaderScreenState();
}

class _LoaderScreenState extends State<LoaderScreen> with TickerProviderStateMixin {
  late final AnimationController _logo = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  int _pct = 0;
  String _status = kLoadingMessages.first;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _logo.forward();
    _timer = Timer.periodic(const Duration(milliseconds: 45), (t) {
      if (!mounted) return;
      setState(() {
        _pct = (_pct + 1).clamp(0, 100);
        final mi = ((_pct / 100) * (kLoadingMessages.length - 1)).floor().clamp(0, kLoadingMessages.length - 1);
        _status = kLoadingMessages[mi];
      });
      if (_pct >= 100) {
        t.cancel();
        Future.delayed(const Duration(milliseconds: 450), () {
          if (mounted) widget.onDone();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logo.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.3, 0),
            end: Alignment(0.7, 1),
            colors: [Color(0xFF06020f), Color(0xFF050510), Color(0xFF08000a)],
          ),
        ),
        child: Stack(
          children: [
            ..._corners(),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: CurvedAnimation(parent: _logo, curve: Curves.elasticOut),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        RotationTransition(
                          turns: _ring,
                          child: Container(
                            width: 156,
                            height: 156,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color.fromRGBO(0, 229, 255, 0.18)),
                            ),
                          ),
                        ),
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(32),
                            gradient: const LinearGradient(colors: [Color(0xFF00e5ff), Color(0xFF7c3aed), Color(0xFF00e5ff)]),
                            boxShadow: [BoxShadow(color: const Color(0xFF00e5ff).withValues(alpha: 0.5), blurRadius: 24)],
                          ),
                          padding: const EdgeInsets.all(2),
                          child: Container(
                            decoration: BoxDecoration(color: const Color(0xFF0a0018), borderRadius: BorderRadius.circular(30)),
                            child: Icon(Ionicons.football, size: 52, color: Colors.white),
                          ),
                        ),
                        Positioned(
                          bottom: -6,
                          right: -6,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(colors: [Color(0xFF00e5ff), Color(0xFF7c3aed)]),
                              border: Border.all(color: Color(0xFF06020f), width: 2),
                            ),
                            child: Icon(Ionicons.play, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(colors: [Color(0xFF00e5ff), Color(0xFF7c3aed)]).createShader(b),
                    child: Text(
                      'SUPASOKA',
                      style: orbitron(28, weight: FontWeight.w900).copyWith(
                        color: Colors.white,
                        letterSpacing: 8,
                        shadows: const [Shadow(color: Color(0xFF00e5ff), blurRadius: 12)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'LIVE TV  •  STREAMS',
                    style: rajdhani(11, weight: FontWeight.w600).copyWith(
                      color: const Color(0xFF00e5ff).withValues(alpha: 0.7),
                      letterSpacing: 5,
                    ),
                  ),
                  SizedBox(height: 48, width: w * 0.78, child: _ProgressBar(pct: _pct)),
                  const SizedBox(height: 8),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: rajdhani(11, weight: FontWeight.w600).copyWith(
                      color: const Color(0xFF00e5ff).withValues(alpha: 0.65),
                      letterSpacing: 2.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _corners() {
    Widget c(Alignment a, {bool top = true, bool left = true}) {
      return Align(
        alignment: a,
        child: Container(
          margin: const EdgeInsets.all(28),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            border: Border(
              top: top ? const BorderSide(color: Color(0xFF00e5ff), width: 1.5) : BorderSide.none,
              bottom: !top ? const BorderSide(color: Color(0xFF00e5ff), width: 1.5) : BorderSide.none,
              left: left ? const BorderSide(color: Color(0xFF00e5ff), width: 1.5) : BorderSide.none,
              right: !left ? const BorderSide(color: Color(0xFF00e5ff), width: 1.5) : BorderSide.none,
            ),
          ),
        ),
      );
    }

    return [
      c(Alignment.topLeft),
      c(Alignment.topRight, left: false),
      c(Alignment.bottomLeft, top: false),
      c(Alignment.bottomRight, top: false, left: false),
    ];
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.pct});

  final int pct;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('LOADING', style: orbitron(9).copyWith(color: Colors.white38, letterSpacing: 3)),
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(colors: [Color(0xFF00e5ff), Color(0xFF7c3aed)]).createShader(b),
              child: Text('$pct%', style: orbitron(22, weight: FontWeight.w900).copyWith(color: Colors.white)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF00e5ff)),
          ),
        ),
      ],
    );
  }
}
