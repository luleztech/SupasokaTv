import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/player/playback_http_headers.dart';
import 'package:supasoka/player/stream_url_classifier.dart';
import 'package:supasoka/player/stream_url_utils.dart';
import 'package:supasoka/player/web_playback_config.dart';
import 'package:supasoka/player/web_player_html.dart';
import 'package:supasoka/player/web_stream_probe.dart';
import 'package:supasoka/services/playback_service.dart';
import 'package:supasoka/theme/brand_palette.dart';
import 'package:supatv/models/tv_playback_settings.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// In-panel / fullscreen player — media_kit preferred; WebView only when required on Android.
class TvEmbeddedPlayer extends StatefulWidget {
  const TvEmbeddedPlayer({
    super.key,
    required this.channel,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.onPremiumRequired,
    this.expandFocusNode,
  });

  final Channel channel;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onPremiumRequired;
  final FocusNode? expandFocusNode;

  @override
  State<TvEmbeddedPlayer> createState() => _TvEmbeddedPlayerState();
}

class _TvEmbeddedPlayerState extends State<TvEmbeddedPlayer> {
  Player? _player;
  VideoController? _videoController;
  WebViewController? _webController;

  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<bool>? _playingSub;

  bool _webView = false;
  bool _loading = true;
  String? _error;
  bool _qualityApplied = false;
  bool _starting = false;
  int _bootGen = 0;
  TvPlaybackSettings? _settingsListener;

  bool get _isAndroidTvish =>
      !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    try {
      unawaited(WakelockPlus.enable());
    } catch (_) {}
    unawaited(_bootstrap());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.read<TvPlaybackSettings>();
    if (!identical(_settingsListener, settings)) {
      _settingsListener?.removeListener(_onQualityChanged);
      _settingsListener = settings;
      settings.addListener(_onQualityChanged);
    }
  }

  void _onQualityChanged() {
    _qualityApplied = false;
    unawaited(_applyQualityCap(force: true));
  }

  @override
  void didUpdateWidget(covariant TvEmbeddedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      unawaited(_restart());
    }
  }

  Future<void> _restart() async {
    final gen = ++_bootGen;
    await _disposePlayer();
    if (!mounted || gen != _bootGen) return;
    setState(() {
      _loading = true;
      _error = null;
      _webView = false;
      _qualityApplied = false;
    });
    await _bootstrap(gen: gen);
  }

  Future<void> _bootstrap({int? gen}) async {
    final myGen = gen ?? ++_bootGen;
    if (_starting) return;
    _starting = true;
    try {
      final resolved = await resolveChannelPlayback(widget.channel.id);
      if (!mounted || myGen != _bootGen) return;

      switch (resolved.code) {
        case PlaybackResolveCode.updateRequired:
        case PlaybackResolveCode.unavailable:
          setState(() {
            _loading = false;
            _error = 'Haikuweza kucheza mfululizo. Jaribu tena.';
          });
          return;
        case PlaybackResolveCode.premiumRequired:
          setState(() => _loading = false);
          widget.onPremiumRequired();
          return;
        case PlaybackResolveCode.ok:
          final session = sessionWithResolvedAudioLanguage(resolved.session!, widget.channel);
          await _startPlayback(session, myGen);
      }
    } finally {
      _starting = false;
    }
  }

  Future<({String url, Map<String, String> headers})?> _probeDirectStream({
    required String url,
    required ApiPlaybackSession session,
    required Map<String, String> headers,
  }) async {
    if (!StreamUrlClassifier.needsWebPlayer(url)) {
      return (url: url, headers: headers);
    }
    try {
      final config = WebPlaybackConfig(
        url: url,
        headers: headers,
        drmType: session.drm,
        licenseUrl: session.licenseUrl,
        clearKeyRaw: session.clearKeyKidKey,
        token: '',
      );
      final resolved = await WebStreamProbe.resolve(config).timeout(
        const Duration(seconds: 4),
      );
      if (resolved.kind == WebResolvedKind.gatewayEmbed) return null;
      return (url: resolved.playbackUrl, headers: resolved.headers);
    } catch (e, st) {
      if (kDebugMode) debugPrint('SupaTV probe failed: $e\n$st');
      return null;
    }
  }

  Future<void> _startPlayback(ApiPlaybackSession session, int gen) async {
    final url = session.streamUrl.trim();
    if (url.isEmpty) {
      if (!mounted || gen != _bootGen) return;
      setState(() {
        _loading = false;
        _error = 'Hakuna mfululizo kwa kituo hiki.';
      });
      return;
    }

    final headers = mergePlaybackHeaders(url, session.playbackHeaders);
    final needsWebPlayer = useWebViewForUrl(url) ||
        session.drm.trim().toLowerCase() != 'none' ||
        session.clearKeyKidKey.trim().isNotEmpty ||
        session.licenseUrl.trim().isNotEmpty;

    if (needsWebPlayer) {
      final probed = await _probeDirectStream(url: url, session: session, headers: headers);
      if (!mounted || gen != _bootGen) return;
      if (probed != null) {
        await _initMediaKit(url: probed.url, headers: probed.headers, gen: gen);
        return;
      }
      // Prefer media_kit first on Android TV — WebView often freezes low-end boxes.
      await _initMediaKit(url: url, headers: headers, gen: gen);
      if (!mounted || gen != _bootGen) return;
      if (_error != null && tvPlatformSupportsWebView()) {
        setState(() {
          _error = null;
          _loading = true;
        });
        await _initWebView(url: url, session: session, headers: headers, gen: gen);
      }
      return;
    }

    await _initMediaKit(url: url, headers: headers, gen: gen);
  }

  Future<void> _initMediaKit({
    required String url,
    required Map<String, String> headers,
    required int gen,
  }) async {
    await _disposePlayer();
    if (!mounted || gen != _bootGen) return;

    final player = Player(
      configuration: PlayerConfiguration(
        title: 'SupaTV',
        bufferSize: 24 * 1024 * 1024,
        ready: () {
          if (kDebugMode) debugPrint('SupaTV player ready');
        },
      ),
    );
    _player = player;
    _videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        hwdec: _isAndroidTvish ? 'auto-safe' : 'auto',
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );

    await _playingSub?.cancel();
    _playingSub = player.stream.playing.listen((playing) {
      if (!mounted || !playing) return;
      if (!_loading) return;
      setState(() => _loading = false);
    });

    try {
      await player.open(Media(url, httpHeaders: headers), play: true).timeout(
        const Duration(seconds: 12),
      );
      if (!mounted || gen != _bootGen) return;

      _tracksSub = player.stream.tracks.listen((_) => unawaited(_applyQualityCap()));
      unawaited(Future<void>.delayed(const Duration(milliseconds: 80), _applyQualityCap));

      if (mounted) {
        setState(() {
          _loading = false;
          _webView = false;
          _error = null;
        });
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('SupaTV media_kit failed: $e\n$st');
      if (!mounted || gen != _bootGen) return;
      setState(() {
        _loading = false;
        _error = 'Haikuweza kucheza mfululizo. Jaribu kituo kingine.';
      });
    }
  }

  Future<void> _initWebView({
    required String url,
    required ApiPlaybackSession session,
    required Map<String, String> headers,
    required int gen,
  }) async {
    if (!tvPlatformSupportsWebView()) {
      if (!mounted || gen != _bootGen) return;
      setState(() {
        _loading = false;
        _error = 'Kituo hiki kinahitaji WebView.';
      });
      return;
    }

    try {
      final controller = WebViewController();
      _webController = controller;
      controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      controller.setBackgroundColor(Colors.black);

      final config = WebPlaybackConfig(
        url: url,
        headers: headers,
        drmType: session.drm,
        licenseUrl: session.licenseUrl,
        clearKeyRaw: session.clearKeyKidKey,
        token: '',
      );
      final resolved = await WebStreamProbe.resolve(config).timeout(
        const Duration(seconds: 6),
      );
      if (!mounted || gen != _bootGen) return;
      final html = _htmlForProbe(resolved);
      await controller.loadHtmlString(html);
      if (!mounted || gen != _bootGen) return;
      setState(() {
        _loading = false;
        _webView = true;
        _error = null;
      });
    } catch (e, st) {
      if (kDebugMode) debugPrint('SupaTV webview failed: $e\n$st');
      if (!mounted || gen != _bootGen) return;
      setState(() {
        _loading = false;
        _error = 'Haikuweza kucheza mfululizo.';
      });
    }
  }

  String _htmlForProbe(WebStreamProbeResult result) {
    final headers = result.headers;
    switch (result.kind) {
      case WebResolvedKind.dash:
      case WebResolvedKind.hls:
      case WebResolvedKind.adaptive:
        return WebPlayerHtml.shaka(
          result.playbackUrl,
          headers,
          drmType: result.drmType,
          licenseUrl: result.licenseUrl,
          clearKeyRaw: result.clearKeyRaw,
        );
      case WebResolvedKind.progressive:
        return WebPlayerHtml.progressive(result.playbackUrl);
      case WebResolvedKind.gatewayEmbed:
        return WebPlayerHtml.gatewayEmbed(result.playbackUrl);
    }
  }

  Future<void> _applyQualityCap({bool force = false}) async {
    if (!mounted || _webView) return;
    if (!force && _qualityApplied) return;
    final maxH = context.read<TvPlaybackSettings>().maxHeight ?? 480;
    final tracks = _player?.state.tracks.video ?? [];
    if (tracks.isEmpty) return;
    if (tracks.length == 1) {
      _qualityApplied = true;
      return;
    }
    _qualityApplied = true;
    await _selectNearestHeight(maxH);
  }

  Future<void> _selectNearestHeight(int maxHeight) async {
    final p = _player;
    if (p == null) return;
    final tracks = p.state.tracks.video;
    if (tracks.isEmpty) return;

    VideoTrack? bestUnder;
    var bestUnderH = -1;
    VideoTrack? smallest;
    var smallestH = 1 << 30;

    for (final t in tracks) {
      final h = t.h ?? 0;
      if (h <= 0) continue;
      if (h <= maxHeight && h > bestUnderH) {
        bestUnder = t;
        bestUnderH = h;
      }
      if (h < smallestH) {
        smallest = t;
        smallestH = h;
      }
    }

    final pick = bestUnder ?? smallest;
    if (pick == null) return;
    try {
      await p.setVideoTrack(pick);
    } catch (e, st) {
      if (kDebugMode) debugPrint('SupaTV setVideoTrack: $e\n$st');
    }
  }

  Future<void> _disposePlayer() async {
    await _tracksSub?.cancel();
    _tracksSub = null;
    await _playingSub?.cancel();
    _playingSub = null;
    final p = _player;
    _player = null;
    _videoController = null;
    _webController = null;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _bootGen++;
    _settingsListener?.removeListener(_onQualityChanged);
    unawaited(_disposePlayer());
    try {
      unawaited(WakelockPlus.disable());
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: BrandPalette.accent),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    const SizedBox(height: 14),
                    Focus(
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            (event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey == LogicalKeyboardKey.select)) {
                          unawaited(_restart());
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: FilledButton(
                        onPressed: () => unawaited(_restart()),
                        child: const Text('Jaribu tena'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_webView && _webController != null)
            WebViewWidget(controller: _webController!)
          else if (_videoController != null)
            Video(
              controller: _videoController!,
              controls: NoVideoControls,
              fit: BoxFit.cover,
              fill: Colors.black,
            ),
          if (!widget.fullscreen && !_loading && _error == null)
            Positioned(
              right: 8,
              bottom: 8,
              child: _TvExpandButton(
                focusNode: widget.expandFocusNode,
                onPressed: widget.onToggleFullscreen,
              ),
            ),
        ],
      ),
    );
  }
}

class _TvExpandButton extends StatefulWidget {
  const _TvExpandButton({
    required this.onPressed,
    this.focusNode,
  });

  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  State<_TvExpandButton> createState() => _TvExpandButtonState();
}

class _TvExpandButtonState extends State<_TvExpandButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.space) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: _focused ? BrandPalette.accent : Colors.black54,
        shape: const CircleBorder(),
        elevation: _focused ? 8 : 0,
        child: IconButton(
          tooltip: 'Panua skrini',
          onPressed: widget.onPressed,
          iconSize: 28,
          icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
        ),
      ),
    );
  }
}
