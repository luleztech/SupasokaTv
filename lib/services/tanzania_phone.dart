/// Normalizes user input to Tanzanian national format `0XXXXXXXXX` (10 digits).
/// Accepts local numbers, `+255…`, `255…`, and 9-digit national without leading `0`.
/// Rejects non‑Tanzania country codes (only +255 / 255).
class TanzaniaPhone {
  TanzaniaPhone._();

  /// All standard TZ mobile NDC blocks: 061–069 and 070–079.
  static final RegExp _mobileLocalRe = RegExp(r'^0(6[1-9]|7[0-9])\d{7}$');

  /// Documented operator prefixes (subset of [_mobileLocalRe]).
  static const knownPrefixes = [
    '061', '062', '063',
    '064',
    '065', '067', '070', '071', '077',
    '066',
    '068', '069', '078',
    '072',
    '073',
    '074', '075', '076', '079',
  ];

  static bool _isValidLocal(String local0) => _mobileLocalRe.hasMatch(local0);

  /// Returns normalized `0XXXXXXXXX` or `null` if not a valid TZ mobile.
  static String? normalize(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return null;

    final upper = s.toUpperCase();
    if (upper.startsWith('+') && !upper.startsWith('+255')) return null;
    if (upper.startsWith('00') && !upper.startsWith('00255')) return null;

    if (upper.startsWith('+255')) {
      s = '0${s.substring(4)}';
    } else if (upper.startsWith('00255')) {
      s = '0${s.substring(5)}';
    } else if (RegExp(r'^255\d{9,}$').hasMatch(s.replaceAll(RegExp(r'\D'), ''))) {
      final digits = s.replaceAll(RegExp(r'\D'), '');
      s = '0${digits.substring(3, digits.length.clamp(3, 12))}';
      if (s.length > 10) s = s.substring(0, 10);
    }

    s = s.replaceAll(RegExp(r'\D'), '');
    if (s.length == 9 && RegExp(r'^[1-9]').hasMatch(s)) {
      s = '0$s';
    }

    if (s.length > 10) s = s.substring(0, 10);

    if (!_isValidLocal(s)) return null;
    return s;
  }

  static bool isValid(String raw) => normalize(raw) != null;

  /// Short label for payment UI (Swahili).
  static String networksHint() =>
      'Nambari zote za Tanzania zinakubalika: 061, 062, 063, 065, 068, 071, 072, 075, 076, 077, 078, 079, na zingine 061–079.';
}
