/// Normalizes user input to Tanzanian national format `0XXXXXXXXX` (10 digits).
/// Accepts local numbers, `+255…`, `255…`, and 9-digit national without leading `0`.
/// Rejects non‑Tanzania country codes (only +255 / 255).
class TanzaniaPhone {
  TanzaniaPhone._();

  /// Operational / assigned TZ mobile NDC prefixes (061–079).
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

  /// Returns normalized `07XXXXXXXX` style or `null` if not a valid TZ mobile.
  static String? normalize(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return null;

    final upper = s.toUpperCase();
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

    // TZ MSISDN: leading 0 + 9 digits; second digit 1–9 (not 00…).
    if (!RegExp(r'^0[1-9]\d{8}$').hasMatch(s)) {
      return null;
    }

    if (!knownPrefixes.any((p) => s.startsWith(p))) {
      return null;
    }
    return s;
  }

  static bool isValid(String raw) => normalize(raw) != null;

  /// Short label for payment UI (Swahili).
  static String networksHint() =>
      'Mitandao: Halotel (061–063), Yas/Tigo (065,067,070,071,077), Airtel (068–069,078), Vodacom (074–076,079), TTCL (073), na zaidi.';
}
