import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/user_identity.dart';
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
  bool _bootStarted = false;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _logo.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_bootStarted) return;
    _bootStarted = true;
    if (!mounted) return;

    final online = await _hasInternetConnection();
    if (!mounted) return;
    if (!online) {
      setState(() {
        _offline = true;
        _status = 'Mtandao haupatikani';
      });
      _bootStarted = false;
      return;
    }

    setState(() {
      _offline = false;
      _status = kLoadingMessages.first;
    });

    await context.read<ContentStore>().bootstrap();
    await UserIdentity.registerWithBackend();
    if (!mounted) return;
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

  Future<bool> _hasInternetConnection() async {
    try {
      final socket = await Socket.connect('1.1.1.1', 53, timeout: const Duration(seconds: 4));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
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

    if (_offline) {
      return Scaffold(body: _NoInternetModal(onRetry: _start));
    }

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


class _NoInternetModal extends StatelessWidget {
  const _NoInternetModal({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: Color(0xFF0B0B0B)),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF11131B),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.18)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.16),
                      blurRadius: 32,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [Color(0xFF00e5ff), Color(0xFF7c3aed)]),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Ionicons.cloud_offline_outline, size: 32, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Hakuna Internet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Washa data na uwe na MB ili uweze kufurahia huduma zetu. Ahsante.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Jaribu tena', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Tafadhali hakikisha una mtandao kabla ya kuendelea.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
