import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeKey { dark, neon, gold, crimson }

class AppThemeColors {
  const AppThemeColors({
    required this.bg1,
    required this.bg2,
    required this.card,
    required this.border,
    required this.accent,
    required this.accent2,
    required this.glow,
    required this.glow2,
    required this.gold,
    required this.text,
    required this.text2,
    required this.navBg,
    required this.premium,
    required this.free,
    required this.red,
  });

  final Color bg1;
  final Color bg2;
  final Color card;
  final Color border;
  final Color accent;
  final Color accent2;
  final Color glow;
  final Color glow2;
  final Color gold;
  final Color text;
  final Color text2;
  final Color navBg;
  final Color premium;
  final Color free;
  final Color red;
}

/// Supastream-inspired neutral shell (surface + zinc) with theme accent pairs.
const Map<ThemeKey, AppThemeColors> kAppThemes = {
  /// Default / “black” theme — near‑pure black surfaces for OLED-friendly UI.
  ThemeKey.dark: AppThemeColors(
    bg1: Color(0xFF000000),
    bg2: Color(0xFF050508),
    card: Color(0xFF121215),
    border: Color(0xFF27272a),
    accent: Color(0xFFe8002d),
    accent2: Color(0xFFfb7185),
    glow: Color.fromRGBO(232, 0, 45, 0.35),
    glow2: Color.fromRGBO(251, 113, 133, 0.3),
    gold: Color(0xFFeab308),
    text: Color(0xFFfafafa),
    text2: Color(0xFFa1a1aa),
    navBg: Color(0xF5000000),
    premium: Color(0xFFeab308),
    free: Color(0xFF22c55e),
    red: Color(0xFFdc2626),
  ),
  ThemeKey.neon: AppThemeColors(
    bg1: Color(0xFF0a0a0a),
    bg2: Color(0xFF111111),
    card: Color(0xFF18181b),
    border: Color(0xFF27272a),
    accent: Color(0xFFa855f7),
    accent2: Color(0xFFec4899),
    glow: Color.fromRGBO(168, 85, 247, 0.35),
    glow2: Color.fromRGBO(236, 72, 153, 0.3),
    gold: Color(0xFFeab308),
    text: Color(0xFFfafafa),
    text2: Color(0xFFa1a1aa),
    navBg: Color(0xF5000000),
    premium: Color(0xFFeab308),
    free: Color(0xFF22c55e),
    red: Color(0xFFdc2626),
  ),
  ThemeKey.gold: AppThemeColors(
    bg1: Color(0xFF0a0a0a),
    bg2: Color(0xFF111111),
    card: Color(0xFF18181b),
    border: Color(0xFF27272a),
    accent: Color(0xFFf59e0b),
    accent2: Color(0xFFfbbf24),
    glow: Color.fromRGBO(245, 158, 11, 0.35),
    glow2: Color.fromRGBO(251, 191, 36, 0.3),
    gold: Color(0xFFeab308),
    text: Color(0xFFfafafa),
    text2: Color(0xFFa1a1aa),
    navBg: Color(0xF5000000),
    premium: Color(0xFFeab308),
    free: Color(0xFF22c55e),
    red: Color(0xFFdc2626),
  ),
  ThemeKey.crimson: AppThemeColors(
    bg1: Color(0xFF0a0a0a),
    bg2: Color(0xFF111111),
    card: Color(0xFF18181b),
    border: Color(0xFF27272a),
    accent: Color(0xFFe8002d),
    accent2: Color(0xFFfb7185),
    glow: Color.fromRGBO(232, 0, 45, 0.35),
    glow2: Color.fromRGBO(251, 113, 133, 0.3),
    gold: Color(0xFFeab308),
    text: Color(0xFFfafafa),
    text2: Color(0xFFa1a1aa),
    navBg: Color(0xF5000000),
    premium: Color(0xFFeab308),
    free: Color(0xFF22c55e),
    red: Color(0xFFdc2626),
  ),
};

class ThemeController extends ChangeNotifier {
  ThemeController._(this._key);

  static const _prefsKey = 'supasoka_app_theme_v2';
  static const _prefsKeyLegacy = 'supasoka_app_theme_v1';

  /// Load saved theme (or default red [ThemeKey.crimson]). Call once from `main()` before `runApp`.
  static Future<ThemeController> load() async {
    final p = await SharedPreferences.getInstance();
    String? raw = p.getString(_prefsKey);

    if (raw == null) {
      raw = p.getString(_prefsKeyLegacy);
      if (raw != null) {
        // One-time upgrade from v1: old blue "dark" default → red Crimson (user-requested default).
        if (raw == ThemeKey.dark.name) raw = ThemeKey.crimson.name;
        await p.setString(_prefsKey, raw);
        await p.remove(_prefsKeyLegacy);
      } else {
        raw = ThemeKey.crimson.name;
        await p.setString(_prefsKey, raw);
      }
    }

    var key = ThemeKey.crimson;
    for (final v in ThemeKey.values) {
      if (v.name == raw) {
        key = v;
        break;
      }
    }
    return ThemeController._(key);
  }

  ThemeKey _key;

  ThemeKey get themeKey => _key;

  AppThemeColors get colors => kAppThemes[_key]!;

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, _key.name);
  }

  void setTheme(ThemeKey key) {
    if (_key == key) return;
    _key = key;
    notifyListeners();
    _persist();
  }
}

class AppNav extends ChangeNotifier {
  int _tab = 0;

  int get currentTab => _tab;

  /// Returns true if the tab actually changed (caller may refresh content).
  bool setTab(int index) {
    if (_tab == index) return false;
    _tab = index;
    notifyListeners();
    return true;
  }
}
