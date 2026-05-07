/// CDNs / `.php` gateways often reject ExoPlayer/WebView without a browser-like [Referer].
Map<String, String> playbackHttpHeaders(String rawUrl) {
  final u = rawUrl.trim();
  if (u.isEmpty) return const {};
  Uri parsed;
  try {
    parsed = Uri.parse(u);
  } catch (_) {
    return const {};
  }
  if (!parsed.hasScheme || !parsed.hasAuthority) return const {};
  final origin = '${parsed.scheme}://${parsed.authority}';
  var referer = u;
  final hash = referer.indexOf('#');
  if (hash >= 0) referer = referer.substring(0, hash);
  return {
    'Referer': referer,
    'Origin': origin,
    'Accept-Language': 'en-US,en;q=0.9,sw;q=0.8',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,application/dash+xml,application/vnd.apple.mpegurl;q=0.8,*/*;q=0.7',
  };
}
