/// Strips line breaks and control characters that are often pasted into admin CMS
/// and break [Uri] / HTTP image loading (e.g. a filename split across two lines).
String stripUnsafeUrlWhitespace(String? raw) {
  if (raw == null) return '';
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.replaceAll(RegExp(r'[\r\n\t\f\v]+'), '');
  return s;
}

/// Image poster / thumb URLs only: must be `http` or `https` after cleanup.
String sanitizeImageUrl(String? raw) {
  final s = stripUnsafeUrlWhitespace(raw);
  if (s.isEmpty) return '';
  final u = Uri.tryParse(s);
  if (u == null || !u.hasScheme) return '';
  if (u.scheme != 'http' && u.scheme != 'https') return '';
  return s;
}
