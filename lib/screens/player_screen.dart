import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/player/php_gateway_js.dart';
import 'package:supasoka/player/stream_url_classifier.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.channelId});

  final int channelId;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late int _channelId;

  VideoPlayerController? _video;
  ChewieController? _chewie;
  WebViewController? _web;

  bool _loading = true;
  String? _error;
  bool _useWebView = false;

  @override
  void initState() {
    super.initState();
    _channelId = widget.channelId;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final ch = _ch;
    final url = ch.streamUrl.trim();
    if (url.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Hakuna URL ya mfululizo kwa kituo hiki.';
      });
      return;
    }

    _useWebView = StreamUrlClassifier.isPhpLikeUrl(url);
    if (_useWebView) {
      await _initWebView(url);
    } else {
      await _initNativePlayer(url);
    }
  }

  Channel get _ch => channelById(_channelId) ?? kChannels.first;

  Future<void> _initWebView(String url) async {
    try {
      // Build controller in steps so closures can close over `controller` after it exists
      // (cascade + onPageFinished caused "referenced before declared" on web compile).
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setUserAgent(kBrowserPlaybackUserAgent);
      await controller.setBackgroundColor(Colors.black);
      await controller.enableZoom(true);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            controller.runJavaScript(kPhpGatewayRecoveryJs);
          },
          onWebResourceError: (WebResourceError error) {
            if (!mounted) return;
            if (_error == null && error.errorCode != -3) {
              setState(() => _error = error.description);
            }
          },
        ),
      );

      await controller.loadRequest(Uri.parse(url));
      if (!mounted) return;
      setState(() {
        _web = controller;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'WebView: $e';
      });
    }
  }

  Future<void> _initNativePlayer(String url) async {
    final t = context.read<ThemeController>().colors;
    try {
      final uri = Uri.parse(url);
      final video = VideoPlayerController.networkUrl(uri);
      await video.initialize();

      final chewie = ChewieController(
        videoPlayerController: video,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        showControlsOnInitialize: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: t.accent,
          handleColor: t.accent2,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
        aspectRatio: video.value.aspectRatio > 0 ? video.value.aspectRatio : 16 / 9,
        errorBuilder: (_, msg) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              msg,
              textAlign: TextAlign.center,
              style: rajdhani(14).copyWith(color: Colors.white70),
            ),
          ),
        ),
      );

      if (!mounted) {
        chewie.dispose();
        await video.dispose();
        return;
      }

      setState(() {
        _video = video;
        _chewie = chewie;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Imeshindikana kucheza: $e';
      });
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _video?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _reloadWeb() async {
    final w = _web;
    final url = _ch.streamUrl.trim();
    if (w == null || url.isEmpty) return;
    setState(() => _loading = true);
    await w.loadRequest(Uri.parse(url));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final ch = _ch;
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          _PlayerChrome(
            top: top,
            title: ch.name,
            subtitle: _useWebView ? 'Kivinjari · PHP gateway' : 'ExoPlayer · mfululizo',
            accent: t.accent,
            accent2: t.accent2,
            onBack: () => Navigator.of(context).pop(),
            onReload: _useWebView && _web != null ? _reloadWeb : null,
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _buildStage(t),
                ),
                if (_loading)
                  const ColoredBox(
                    color: Color(0xFF0a0a0a),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF00e5ff)),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Inapakia mfululizo…',
                            style: TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStage(AppThemeColors t) {
    if (_error != null && !_loading) {
      return _ErrorPane(message: _error!, accent: t.accent, onRetry: () {
        setState(() {
          _error = null;
          _loading = true;
        });
        _bootstrap();
      });
    }

    if (_useWebView && _web != null) {
      return Container(
        color: Colors.black,
        child: WebViewWidget(controller: _web!),
      );
    }

    if (!_useWebView && _chewie != null && _video != null) {
      return Chewie(controller: _chewie!);
    }

    return const SizedBox.shrink();
  }
}

class _PlayerChrome extends StatelessWidget {
  const _PlayerChrome({
    required this.top,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.accent2,
    required this.onBack,
    this.onReload,
  });

  final double top;
  final String title;
  final String subtitle;
  final Color accent;
  final Color accent2;
  final VoidCallback onBack;
  final Future<void> Function()? onReload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, top + 6, 12, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromRGBO(0, 0, 0, 0.92),
            Color.fromRGBO(0, 0, 0, 0.55),
            Colors.transparent,
          ],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onBack,
              child: const SizedBox(
                width: 42,
                height: 42,
                child: Icon(Ionicons.chevron_back, color: Colors.white, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: orbitron(15, weight: FontWeight.w800).copyWith(color: Colors.white, letterSpacing: 0.3),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: rajdhani(11, weight: FontWeight.w500).copyWith(color: Colors.white54, letterSpacing: 0.4),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(colors: [accent.withValues(alpha: 0.35), accent2.withValues(alpha: 0.25)]),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: accent, blurRadius: 8)]),
                ),
                const SizedBox(width: 6),
                Text('LIVE', style: orbitron(9, weight: FontWeight.w900).copyWith(color: Colors.white, letterSpacing: 1.6)),
              ],
            ),
          ),
          if (onReload != null) ...[
            const SizedBox(width: 8),
            Material(
              color: Colors.white.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: InkWell(
                onTap: () => onReload!(),
                child: const SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(Ionicons.refresh_outline, color: Colors.white70, size: 20),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.accent, required this.onRetry});

  final String message;
  final Color accent;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0d0d0d),
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Ionicons.alert_circle_outline, size: 48, color: accent.withValues(alpha: 0.85)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: rajdhani(14, weight: FontWeight.w500).copyWith(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Ionicons.reload_outline, size: 18),
              label: Text('Jaribu tena', style: rajdhani(14, weight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
