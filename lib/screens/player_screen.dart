import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/player/php_gateway_js.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/native_android_player.dart';
import 'package:supasoka/player/playback_http_headers.dart';
import 'package:supasoka/player/stream_url_classifier.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Shown for any stream/decoder failure — never expose URLs, stack traces, or PlatformException text.
const _kPlaybackUnavailableCopy =
    'Mafundi wetu wanafanyia kazi. Channel itarejea hivi punde.';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.channelId});

  final int channelId;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _PlayerIssue {
  /// Config / list problem — still non-technical (no IDs or URLs).
  missingChannel,
  noStreamUrl,
  playbackUnavailable,
}

String _copyForIssue(_PlayerIssue issue) {
  switch (issue) {
    case _PlayerIssue.missingChannel:
      return 'Kituo hakipatikani. Jaribu tena baadaye.';
    case _PlayerIssue.noStreamUrl:
      return 'Kituo hiki hakina mfululizo kwa sasa.';
    case _PlayerIssue.playbackUnavailable:
      return _kPlaybackUnavailableCopy;
  }
}

String _nativeDrmTypeFor(Channel channel) {
  final drm = channel.drm.trim().toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');
  switch (drm) {
    case 'clearkey':
      return channel.clearKeyKidKey.trim().isEmpty ? 'NONE' : 'CLEARKEY';
    case 'widevine':
      return 'WIDEVINE';
    case 'widevinel1':
      return 'WIDEVINE_L1';
    case 'widevinel3':
      return 'WIDEVINE_L3';
    case 'playready':
      return 'PLAYREADY';
    default:
      return 'NONE';
  }
}

class _PlayerScreenState extends State<PlayerScreen> {
  late int _channelId;
  Channel? _channel;

  VideoPlayerController? _video;
  ChewieController? _chewie;
  WebViewController? _web;

  bool _loading = true;
  _PlayerIssue? _issue;
  bool _useWebView = false;
  /// On web, retry once with WebView when video_player (HLS/DASH) fails.
  bool _webFallbackAttempted = false;

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
    final store = context.read<ContentStore>();
    final ch = store.channelById(_channelId);
    _channel = ch;
    if (ch == null) {
      setState(() {
        _loading = false;
        _issue = _PlayerIssue.missingChannel;
      });
      return;
    }
    final url = ch.streamUrl.trim();
    if (url.isEmpty) {
      setState(() {
        _loading = false;
        _issue = _PlayerIssue.noStreamUrl;
      });
      return;
    }

    if (NativeAndroidPlayer.supported) {
      await NativeAndroidPlayer.open(
        url: url,
        licenseUrl: ch.licenseUrl.trim(),
        drmType: _nativeDrmTypeFor(ch),
        clearKeyHex: ch.clearKeyKidKey.trim(),
        headers: playbackHttpHeaders(url),
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final isPhpGateway = StreamUrlClassifier.isPhpLikeUrl(url);
    final hasDirectStream = StreamUrlClassifier.hasObviousM3u8(url) ||
        StreamUrlClassifier.hasObviousMpd(url) ||
        StreamUrlClassifier.hasObviousTs(url);
    _useWebView = isPhpGateway && !hasDirectStream;
    if (_useWebView) {
      await _initWebView(url);
    } else {
      await _initNativePlayer(url);
    }
  }

  Future<void> _initWebView(String url) async {
    try {
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
            // -3 is often cancelled navigation; ignore for UX.
            if (error.errorCode == -3) return;
            setState(() {
              _loading = false;
              _issue = _PlayerIssue.playbackUnavailable;
            });
          },
        ),
      );

      final headers = playbackHttpHeaders(url);
      await controller.loadRequest(
        Uri.parse(url),
        headers: Map<String, String>.from(headers),
      );
      if (!mounted) return;
      setState(() {
        _web = controller;
        _loading = false;
        _issue = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _issue = _PlayerIssue.playbackUnavailable;
      });
    }
  }

  VideoFormat? _formatHintForUrl(String url) {
    if (StreamUrlClassifier.hasObviousM3u8(url)) return VideoFormat.hls;
    if (StreamUrlClassifier.hasObviousMpd(url)) return VideoFormat.dash;
    return null;
  }

  void _onNativeVideoEvent() {
    final v = _video;
    if (v == null || !mounted || _useWebView) return;
    if (!v.value.hasError) return;

    assert(() {
      debugPrint('Supasoka player: native stream error (details omitted in UI)');
      return true;
    }());

    final url = _channel?.streamUrl.trim() ?? '';
    if (url.isEmpty) {
      _disposeNativeControllers();
      setState(() {
        _loading = false;
        _issue = _PlayerIssue.playbackUnavailable;
      });
      return;
    }

    if (kIsWeb && !_webFallbackAttempted) {
      _webFallbackAttempted = true;
      unawaited(_switchFromNativeToWebView(url));
      return;
    }

    _disposeNativeControllers();
    setState(() {
      _loading = false;
      _issue = _PlayerIssue.playbackUnavailable;
    });
  }

  Future<void> _switchFromNativeToWebView(String url) async {
    _video?.removeListener(_onNativeVideoEvent);
    _chewie?.dispose();
    _chewie = null;
    await _video?.dispose();
    _video = null;
    if (!mounted) return;
    _useWebView = true;
    setState(() {
      _loading = true;
      _issue = null;
    });
    await _initWebView(url);
  }

  void _disposeNativeControllers() {
    _video?.removeListener(_onNativeVideoEvent);
    _chewie?.dispose();
    _chewie = null;
    _video?.dispose();
    _video = null;
  }

  Future<void> _initNativePlayer(String url) async {
    final t = context.read<ThemeController>().colors;
    try {
      final uri = Uri.parse(url);
      final formatHint = _formatHintForUrl(url);

      final headers = playbackHttpHeaders(url);
      final video = formatHint != null
          ? VideoPlayerController.networkUrl(uri, formatHint: formatHint, httpHeaders: headers)
          : VideoPlayerController.networkUrl(uri, httpHeaders: headers);
      await video.initialize();
      video.addListener(_onNativeVideoEvent);

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
        errorBuilder: (context, errorMessage) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _kPlaybackUnavailableCopy,
            textAlign: TextAlign.center,
            style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white70, height: 1.35),
          ),
        ),
      );

      if (!mounted) {
        chewie.dispose();
        video.removeListener(_onNativeVideoEvent);
        await video.dispose();
        return;
      }

      setState(() {
        _video = video;
        _chewie = chewie;
        _loading = false;
        _issue = null;
      });
    } catch (_) {
      assert(() {
        debugPrint('Supasoka player: init failed (details omitted in UI)');
        return true;
      }());

      if (mounted && kIsWeb && !_webFallbackAttempted && !_useWebView) {
        _webFallbackAttempted = true;
        _useWebView = true;
        setState(() {
          _loading = true;
          _issue = null;
        });
        await _initWebView(url);
        return;
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _issue = _PlayerIssue.playbackUnavailable;
      });
    }
  }

  Future<void> _resetAndBootstrap() async {
    _disposeNativeControllers();
    _web = null;
    setState(() {
      _issue = null;
      _loading = true;
      _webFallbackAttempted = false;
      _useWebView = false;
    });
    await _bootstrap();
  }

  @override
  void dispose() {
    _video?.removeListener(_onNativeVideoEvent);
    _chewie?.dispose();
    _video?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _reloadWeb() async {
    final w = _web;
    final url = (_channel?.streamUrl ?? '').trim();
    if (w == null || url.isEmpty) return;
    setState(() => _loading = true);
    final headers = playbackHttpHeaders(url);
    await w.loadRequest(
      Uri.parse(url),
      headers: Map<String, String>.from(headers),
    );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    context.watch<ContentStore>();
    final ch = _channel;
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          _PlayerChrome(
            top: top,
            title: ch?.name ?? 'Kituo',
            subtitle: 'Moja kwa moja',
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
    if (_issue != null && !_loading) {
      return _PlaybackIssueModal(
        message: _copyForIssue(_issue!),
        accent: t.accent,
        accent2: t.accent2,
        onRetry: _resetAndBootstrap,
      );
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

/// Full-bleed friendly card — no technical errors, no URLs.
class _PlaybackIssueModal extends StatelessWidget {
  const _PlaybackIssueModal({
    required this.message,
    required this.accent,
    required this.accent2,
    required this.onRetry,
  });

  final String message;
  final Color accent;
  final Color accent2;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF16161a),
                  const Color(0xFF0c0c0f),
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 28, spreadRadius: -4),
                BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, offset: const Offset(0, 12)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 30, 26, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [accent.withValues(alpha: 0.35), accent2.withValues(alpha: 0.22)]),
                      border: Border.all(color: accent.withValues(alpha: 0.45)),
                    ),
                    child: Icon(Ionicons.construct_outline, size: 36, color: accent),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: rajdhani(16, weight: FontWeight.w600).copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.45,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => onRetry(),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Ionicons.reload_outline, size: 20),
                      label: Text('Jaribu tena', style: rajdhani(15, weight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
