/// URL classification aligned with `/player/StreamUrlClassifier.kt` (EaMax gateway pages).
class StreamUrlClassifier {
  StreamUrlClassifier._();

  /// `.php` gateways — include `.php/` paths (many panels use `/play.php/channel`).
  static bool isPhpLikeUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final u = url.toLowerCase();
    return RegExp(r'\.php(\$|[/?#])', caseSensitive: false).hasMatch(u);
  }

  /// HLS — match `.m3u8` anywhere (path, redirect targets, signed URLs).
  static bool hasObviousM3u8(String url) {
    final u = url.toLowerCase();
    return u.contains('.m3u8');
  }

  /// DASH — match `.mpd` anywhere (manifest URLs, Widevine/ClearKey hosts).
  static bool hasObviousMpd(String url) {
    final u = url.toLowerCase();
    return u.contains('.mpd');
  }

  /// Direct-ish progressive / obvious stream hints when extension is nonstandard.
  static bool hasObviousTs(String url) {
    final u = url.toLowerCase();
    return u.contains('.ts?') || u.endsWith('.ts') || u.contains('.mp4?') || u.endsWith('.mp4');
  }
}

/// Same UA string as `PhpWebViewSupport.BROWSER_PLAYBACK_USER_AGENT` in reference project.
const String kBrowserPlaybackUserAgent =
    'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Mobile Safari/537.36';
