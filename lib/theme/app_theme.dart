import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeKey { dark, neon, gold, crimson }

class AppThemeColors {
  const AppThemeColors({
    required this.bg1,
    required this.bg2,
    required this.card,
    required this.surface,
    required this.border,
    required this.accent,
    required this.accent2,
    required this.glow,
    required this.glow2,
    required this.gold,
    required this.text,
    required this.text2,
    required this.textMuted,
    required this.navBg,
    required this.premium,
    required this.free,
    required this.red,
  });

  final Color bg1;
  final Color bg2;
  final Color card;
  final Color surface;
  final Color border;
  final Color accent;
  final Color accent2;
  final Color glow;
  final Color glow2;
  final Color gold;
  final Color text;
  final Color text2;
  final Color textMuted;
  final Color navBg;
  final Color premium;
  final Color free;
  final Color red;
}

/// Premium cinematic palette — layered blacks, red/orange accent, gold premium.
const Map<ThemeKey, AppThemeColors> kAppThemes = {
  ThemeKey.dark: AppThemeColors(
    bg1: Color(0xFF050505),
    bg2: Color(0xFF0B0B0B),
    card: Color(0xFF111111),
    surface: Color(0xFF171717),
    border: Color(0x14FFFFFF),
    accent: Color(0xFFFF3B30),
    accent2: Color(0xFFFF6B00),
    glow: Color.fromRGBO(255, 59, 48, 0.35),
    glow2: Color.fromRGBO(255, 107, 0, 0.28),
    gold: Color(0xFFFFD700),
    text: Color(0xFFFFFFFF),
    text2: Color(0xFFB0B0B0),
    textMuted: Color(0xFF707070),
    navBg: Color(0xF0050505),
    premium: Color(0xFFFFD700),
    free: Color(0xFF00D26A),
    red: Color(0xFFFF3B30),
  ),
  ThemeKey.neon: AppThemeColors(
    bg1: Color(0xFF050505),
    bg2: Color(0xFF0B0B0B),
    card: Color(0xFF111111),
    surface: Color(0xFF171717),
    border: Color(0x14FFFFFF),
    accent: Color(0xFFa855f7),
    accent2: Color(0xFFec4899),
    glow: Color.fromRGBO(168, 85, 247, 0.35),
    glow2: Color.fromRGBO(236, 72, 153, 0.28),
    gold: Color(0xFFFFD700),
    text: Color(0xFFFFFFFF),
    text2: Color(0xFFB0B0B0),
    textMuted: Color(0xFF707070),
    navBg: Color(0xF0050505),
    premium: Color(0xFFFFD700),
    free: Color(0xFF00D26A),
    red: Color(0xFFFF3B30),
  ),
  ThemeKey.gold: AppThemeColors(
    bg1: Color(0xFF050505),
    bg2: Color(0xFF0B0B0B),
    card: Color(0xFF111111),
    surface: Color(0xFF171717),
    border: Color(0x14FFFFFF),
    accent: Color(0xFFFFD700),
    accent2: Color(0xFFFF6B00),
    glow: Color.fromRGBO(255, 215, 0, 0.32),
    glow2: Color.fromRGBO(255, 107, 0, 0.25),
    gold: Color(0xFFFFD700),
    text: Color(0xFFFFFFFF),
    text2: Color(0xFFB0B0B0),
    textMuted: Color(0xFF707070),
    navBg: Color(0xF0050505),
    premium: Color(0xFFFFD700),
    free: Color(0xFF00D26A),
    red: Color(0xFFFF3B30),
  ),
  ThemeKey.crimson: AppThemeColors(
    bg1: Color(0xFF050505),
    bg2: Color(0xFF0B0B0B),
    card: Color(0xFF111111),
    surface: Color(0xFF171717),
    border: Color(0x14FFFFFF),
    accent: Color(0xFFFF3B30),
    accent2: Color(0xFFFF6B00),
    glow: Color.fromRGBO(255, 59, 48, 0.35),
    glow2: Color.fromRGBO(255, 107, 0, 0.28),
    gold: Color(0xFFFFD700),
    text: Color(0xFFFFFFFF),
    text2: Color(0xFFB0B0B0),
    textMuted: Color(0xFF707070),
    navBg: Color(0xF0050505),
    premium: Color(0xFFFFD700),
    free: Color(0xFF00D26A),
    red: Color(0xFFFF3B30),
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
  int _tab = AppTab.home;

  int get currentTab => _tab;

  /// Returns true if the tab actually changed (caller may refresh content).
  bool setTab(int index) {
    if (_tab == index) return false;
    _tab = index;
    notifyListeners();
    return true;
  }
}

/// Bottom navigation indices (Home · Unlock · Profile).
abstract final class AppTab {
  static const home = 0;
  static const unlock = 1;
  static const profile = 2;
}
