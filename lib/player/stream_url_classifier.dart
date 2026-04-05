/// URL classification aligned with `/player/StreamUrlClassifier.kt` (EaMax gateway pages).
class StreamUrlClassifier {
  StreamUrlClassifier._();

  /// `.php` before query, hash, or end of path → WebView playback (not ExoPlayer direct).
  static bool isPhpLikeUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    return RegExp(r'\.php(\?|$|#)', caseSensitive: false).hasMatch(url);
  }

  static bool hasObviousM3u8(String url) =>
      RegExp(r'\.m3u8(\?|#|$)', caseSensitive: false).hasMatch(url);

  static bool hasObviousMpd(String url) =>
      RegExp(r'\.mpd(\?|#|$)', caseSensitive: false).hasMatch(url);
}

/// Same UA string as `PhpWebViewSupport.BROWSER_PLAYBACK_USER_AGENT` in reference project.
const String kBrowserPlaybackUserAgent =
    'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Mobile Safari/537.36';
