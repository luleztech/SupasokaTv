/// Normalizes user input to Tanzanian national format `0XXXXXXXXX` (10 digits).
/// Accepts local numbers, `+255…`, `255…`, and 9-digit national without leading `0`.
/// Rejects non‑Tanzania country codes (only +255 / 255).
class TanzaniaPhone {
  TanzaniaPhone._();

  /// All standard TZ mobile NDC blocks: 061–069 and 070–079.
  static final RegExp _mobileLocalRe = RegExp(r'^0(6[1-9]|7[0-9])\d{7}$');

  static const vodacomPrefixes = ['074', '075', '076', '079'];

  /// Documented operator prefixes (subset of [_mobileLocalRe]).
  static const knownPrefixes = [
    '061', '062', '063',
    '064',
    '065', '067', '070', '071', '077',
    '066',
    '068', '069', '078',
    '072',
    '073',
    ...vodacomPrefixes,
  ];

  static bool _isValidLocal(String local0) => _mobileLocalRe.hasMatch(local0);

  /// Nine digits after the national `0` (e.g. `712345678` from `0712345678`).
  static String? localBodyDigits(String raw) {
    final local = normalize(raw);
    if (local == null || local.length != 10) return null;
    return local.substring(1);
  }

  /// Validates 9-digit body (without leading `0`) or full 10-digit local input.
  static bool isValidLocalBody(String body) {
    final digits = body.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 9) return isValid('0$digits');
    if (digits.length == 10 && digits.startsWith('0')) return isValid(digits);
    return false;
  }

  /// Build national `0XXXXXXXXX` from fixed `0` prefix + 9-digit body field.
  static String? fromLocalBody(String body) => normalize('0${body.replaceAll(RegExp(r'\D'), '')}');

  /// Returns normalized `0XXXXXXXXX` or `null` if not a valid TZ mobile.
  static String? normalize(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return null;

    final upper = s.toUpperCase();
    if (upper.startsWith('+') && !upper.startsWith('+255')) return null;

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
    // Typo `007…` → `07…` (some keyboards duplicate the leading zero).
    while (s.startsWith('00') && s.length > 10 && RegExp(r'^00[67]').hasMatch(s)) {
      s = '0${s.substring(2)}';
    }
    if (s.startsWith('00') && !s.startsWith('00255')) {
      if (!RegExp(r'^00[67]').hasMatch(s)) return null;
      s = '0${s.substring(2)}';
    }

    if (s.length == 9 && RegExp(r'^[1-9]').hasMatch(s)) {
      s = '0$s';
    }

    if (s.length > 10) s = s.substring(0, 10);

    if (!_isValidLocal(s)) return null;
    return s;
  }

  static bool isValid(String raw) => normalize(raw) != null;

  /// Vodacom M-Pesa prefixes: 074, 075, 076, 079.
  static bool isVodacomMpesa(String raw) {
    final local = normalize(raw);
    if (local == null) return false;
    return vodacomPrefixes.any((pre) => local.startsWith(pre));
  }

  /// Short label for payment UI (Swahili).
  static String networksHint() =>
      'Nambari zote za Tanzania zinakubalika: 061–063, 065, 068, 071, 072, 074–076, 077, 078, 079 (Vodacom: 074, 075, 076, 079).';
}
