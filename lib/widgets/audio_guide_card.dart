import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Premium audio "tap to listen" guide tile.
///
/// Designed to live above the price step on the **Fungua zote** screen, but
/// reusable anywhere — pass an [assetPath] (relative to `assets/`) and a [title].
///
/// UX notes:
/// * Tap anywhere to play / pause / resume.
/// * A pulsing waveform keeps the surface alive while playing without burning
///   battery (single shared [AnimationController]).
/// * Auto-stops on dispose so navigation away doesn't leave audio orphaned.
class AudioGuideCard extends StatefulWidget {
  const AudioGuideCard({
    super.key,
    required this.assetPath,
    required this.title,
    this.subtitle,
    this.accent = const Color(0xFF22C55E),
    this.accentSecondary = const Color(0xFF06B6D4),
  });

  /// e.g. `audio/fungua_zote_guide.mp3` (relative to the `assets/` folder).
  final String assetPath;
  final String title;
  final String? subtitle;
  final Color accent;
  final Color accentSecondary;

  @override
  State<AudioGuideCard> createState() => _AudioGuideCardState();
}

class _AudioGuideCardState extends State<AudioGuideCard>
    with SingleTickerProviderStateMixin {
  late final AudioPlayer _player;
  late final AnimationController _pulse;

  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _loading = false;
  String? _error;

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
    });
    _posSub = _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _state = PlayerState.stopped;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  bool get _isPlaying => _state == PlayerState.playing;
  bool get _hasStarted => _position > Duration.zero || _isPlaying;

  Future<void> _toggle() async {
    if (_loading) return;
    try {
      if (_isPlaying) {
        await _player.pause();
        return;
      }
      if (_state == PlayerState.paused) {
        await _player.resume();
        return;
      }
      setState(() {
        _loading = true;
        _error = null;
      });
      await _player.play(AssetSource(widget.assetPath));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Imeshindikana kuanzisha sauti. Jaribu tena.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stop() async {
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _position = Duration.zero;
      _state = PlayerState.stopped;
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_duration.inMilliseconds == 0)
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

    return Semantics(
      button: true,
      label: widget.title,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            // Soft animated bloom — kept low alpha so it never overpowers content.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final t = _pulse.value;
                  return CustomPaint(
                    painter: _AmbientBloomPainter(
                      t: t,
                      colorA: widget.accent.withValues(alpha: _isPlaying ? 0.32 : 0.18),
                      colorB: widget.accentSecondary.withValues(alpha: _isPlaying ? 0.30 : 0.16),
                    ),
                  );
                },
              ),
            ),
            // Glass surface
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.05),
                      Colors.white.withValues(alpha: 0.02),
                    ],
                  ),
                  border: Border.all(
                    color: widget.accent.withValues(alpha: _isPlaying ? 0.55 : 0.28),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent.withValues(alpha: _isPlaying ? 0.32 : 0.16),
                      blurRadius: _isPlaying ? 28 : 18,
                      spreadRadius: -6,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _toggle,
                    splashColor: widget.accent.withValues(alpha: 0.18),
                    highlightColor: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(22),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _PlayOrb(
                                playing: _isPlaying,
                                loading: _loading,
                                accent: widget.accent,
                                accentSecondary: widget.accentSecondary,
                                pulse: _pulse,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(99),
                                            color: widget.accent.withValues(alpha: 0.18),
                                            border: Border.all(
                                              color: widget.accent.withValues(alpha: 0.35),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.headphones_rounded,
                                                size: 11,
                                                color: widget.accent,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'MWONGOZO WA SAUTI',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 1.2,
                                                  color: widget.accent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      widget.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        height: 1.25,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.1,
                                      ),
                                    ),
                                    if (widget.subtitle != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.subtitle!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white.withValues(alpha: 0.62),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (_hasStarted)
                                _StopButton(onTap: _stop, accent: widget.accent),
                            ],
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            child: _hasStarted
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 14),
                                    child: Column(
                                      children: [
                                        AnimatedBuilder(
                                          animation: _pulse,
                                          builder: (context, _) => _Waveform(
                                            progress: progress,
                                            playing: _isPlaying,
                                            phase: _pulse.value,
                                            accent: widget.accent,
                                            accentSecondary: widget.accentSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _fmt(_position),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                                color: widget.accent.withValues(alpha: 0.95),
                                                letterSpacing: 0.4,
                                              ),
                                            ),
                                            Text(
                                              _duration > Duration.zero ? _fmt(_duration) : '--:--',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                                color: Colors.white.withValues(alpha: 0.55),
                                                letterSpacing: 0.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.red.shade300,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayOrb extends StatelessWidget {
  const _PlayOrb({
    required this.playing,
    required this.loading,
    required this.accent,
    required this.accentSecondary,
    required this.pulse,
  });

  final bool playing;
  final bool loading;
  final Color accent;
  final Color accentSecondary;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final scale = playing ? 1.0 + math.sin(pulse.value * math.pi * 2) * 0.04 : 1.0;
        return SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (playing)
                ...List.generate(2, (i) {
                  final t = (pulse.value + i * 0.5) % 1.0;
                  return Opacity(
                    opacity: (1 - t) * 0.55,
                    child: Container(
                      width: 56 + t * 28,
                      height: 56 + t * 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accent.withValues(alpha: 0.6),
                          width: 1.4,
                        ),
                      ),
                    ),
                  );
                }),
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accent, accentSecondary],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: -2,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, anim) =>
                                ScaleTransition(scale: anim, child: child),
                            child: Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              key: ValueKey(playing),
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
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

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onTap, required this.accent});

  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Icon(
              Icons.stop_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ),
      ),
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.progress,
    required this.playing,
    required this.phase,
    required this.accent,
    required this.accentSecondary,
  });

  final double progress;
  final bool playing;
  final double phase;
  final Color accent;
  final Color accentSecondary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: CustomPaint(
        painter: _WaveformPainter(
          progress: progress,
          playing: playing,
          phase: phase,
          accent: accent,
          accentSecondary: accentSecondary,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.playing,
    required this.phase,
    required this.accent,
    required this.accentSecondary,
  });

  final double progress;
  final bool playing;
  final double phase;
  final Color accent;
  final Color accentSecondary;

  static const _bars = 36;

  @override
  void paint(Canvas canvas, Size size) {
    final barW = 2.6;
    final gap = (size.width - _bars * barW) / (_bars - 1);
    final mid = size.height / 2;
    final activeBar = (progress * _bars).floor();

    for (var i = 0; i < _bars; i++) {
      // Pseudo-random envelope so bars feel like a real waveform without an audio analyser.
      final base = 0.35 +
          0.55 *
              (math.sin(i * 0.65) * 0.5 +
                      math.sin(i * 1.7 + 2.1) * 0.3 +
                      math.cos(i * 0.31 + 1.1) * 0.4)
                  .abs();
      final wobble = playing
          ? math.sin((phase * math.pi * 2) + i * 0.55) * 0.18
          : 0.0;
      final h = ((base + wobble).clamp(0.18, 1.0)) * (size.height - 6);

      final isActive = i <= activeBar;
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barW
        ..shader = isActive
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [accent, accentSecondary],
              ).createShader(Rect.fromLTWH(0, mid - h / 2, size.width, h))
            : null
        ..color = isActive ? Colors.transparent : Colors.white.withValues(alpha: 0.18);

      final x = i * (barW + gap) + barW / 2;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress || old.playing != playing || old.phase != phase;
}

class _AmbientBloomPainter extends CustomPainter {
  _AmbientBloomPainter({
    required this.t,
    required this.colorA,
    required this.colorB,
  });

  final double t;
  final Color colorA;
  final Color colorB;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx1 = w * (0.18 + math.sin(t * math.pi * 2) * 0.06);
    final cy1 = h * 0.5;
    final cx2 = w * (0.82 + math.cos(t * math.pi * 2) * 0.06);
    final cy2 = h * 0.5;

    final r = math.max(w, h) * 0.65;

    canvas.drawCircle(
      Offset(cx1, cy1),
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [colorA, Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(cx1, cy1), radius: r)),
    );
    canvas.drawCircle(
      Offset(cx2, cy2),
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [colorB, Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(cx2, cy2), radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant _AmbientBloomPainter old) =>
      old.t != t || old.colorA != colorA || old.colorB != colorB;
}
