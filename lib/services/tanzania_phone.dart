/// Normalizes user input to Tanzanian national format `0XXXXXXXXX` (10 digits).
/// Accepts local numbers, `+255…`, `255…`, and 9-digit national without leading `0`.
/// Rejects non‑Tanzania country codes (only +255 / 255).
class TanzaniaPhone {
  TanzaniaPhone._();

  /// Returns normalized `07XXXXXXXX` style or `null` if not a valid TZ mobile.
  static String? normalize(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return null;

    if (s.startsWith('+')) {
      if (!s.toUpperCase().startsWith('+255')) return null;
      s = s.substring(4);
    } else if (s.startsWith('255') && s.length > 9) {
      s = s.substring(3);
    } else if (s.startsWith('0') && s.length == 10) {
      // already local
    }

    s = s.replaceAll(RegExp(r'\D'), '');
    if (s.length == 9 && RegExp(r'^[1-9]').hasMatch(s)) {
      s = '0$s';
    }

    // TZ MSISDN: leading 0 + 9 digits; second digit 1–9 (all operators: 62,65,67,68,69,71–78, etc.)
    if (RegExp(r'^0[1-9]\d{8}$').hasMatch(s)) {
      return s;
    }
    return null;
  }

  static bool isValid(String raw) => normalize(raw) != null;
}
