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

const Map<ThemeKey, AppThemeColors> kAppThemes = {
  ThemeKey.dark: AppThemeColors(
    bg1: Color(0xFF0a0a0f),
    bg2: Color(0xFF0f0f1a),
    card: Color.fromRGBO(255, 255, 255, 0.04),
    border: Color.fromRGBO(255, 255, 255, 0.08),
    accent: Color(0xFF00e5ff),
    accent2: Color(0xFF7c3aed),
    glow: Color.fromRGBO(0, 229, 255, 0.4),
    glow2: Color.fromRGBO(124, 58, 237, 0.4),
    gold: Color(0xFFffd700),
    text: Color(0xFFe8eaf6),
    text2: Color(0xFF9e9eb8),
    navBg: Color.fromRGBO(10, 10, 20, 0.97),
    premium: Color(0xFFffd700),
    free: Color(0xFF00e676),
    red: Color(0xFFff1744),
  ),
  ThemeKey.neon: AppThemeColors(
    bg1: Color(0xFF000510),
    bg2: Color(0xFF050520),
    card: Color.fromRGBO(255, 255, 255, 0.04),
    border: Color.fromRGBO(255, 0, 255, 0.12),
    accent: Color(0xFFff00ff),
    accent2: Color(0xFF00ffaa),
    glow: Color.fromRGBO(255, 0, 255, 0.5),
    glow2: Color.fromRGBO(0, 255, 170, 0.4),
    gold: Color(0xFFffd700),
    text: Color(0xFFe8eaf6),
    text2: Color(0xFF9e9eb8),
    navBg: Color.fromRGBO(0, 5, 16, 0.97),
    premium: Color(0xFFffd700),
    free: Color(0xFF00e676),
    red: Color(0xFFff1744),
  ),
  ThemeKey.gold: AppThemeColors(
    bg1: Color(0xFF0d0900),
    bg2: Color(0xFF1a1000),
    card: Color.fromRGBO(255, 255, 255, 0.04),
    border: Color.fromRGBO(255, 215, 0, 0.12),
    accent: Color(0xFFffd700),
    accent2: Color(0xFFff8c00),
    glow: Color.fromRGBO(255, 215, 0, 0.5),
    glow2: Color.fromRGBO(255, 140, 0, 0.4),
    gold: Color(0xFFffd700),
    text: Color(0xFFe8eaf6),
    text2: Color(0xFF9e9eb8),
    navBg: Color.fromRGBO(13, 9, 0, 0.97),
    premium: Color(0xFFffd700),
    free: Color(0xFF00e676),
    red: Color(0xFFff1744),
  ),
  ThemeKey.crimson: AppThemeColors(
    bg1: Color(0xFF0c0005),
    bg2: Color(0xFF140008),
    card: Color.fromRGBO(255, 255, 255, 0.04),
    border: Color.fromRGBO(220, 20, 60, 0.18),
    accent: Color(0xFFe8002d),
    accent2: Color(0xFFff6b6b),
    glow: Color.fromRGBO(232, 0, 45, 0.45),
    glow2: Color.fromRGBO(255, 107, 107, 0.35),
    gold: Color(0xFFffd700),
    text: Color(0xFFf5e6e8),
    text2: Color(0xFFb89099),
    navBg: Color.fromRGBO(12, 0, 5, 0.97),
    premium: Color(0xFFffd700),
    free: Color(0xFF00e676),
    red: Color(0xFFff1744),
  ),
};

class ThemeController extends ChangeNotifier {
  ThemeController._(this._key);

  static const _prefsKey = 'supasoka_app_theme_v1';

  /// Load saved theme (or default). Call once from `main()` before `runApp`.
  static Future<ThemeController> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsKey);
    var key = ThemeKey.dark;
    if (raw != null) {
      for (final v in ThemeKey.values) {
        if (v.name == raw) {
          key = v;
          break;
        }
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

  void setTab(int index) {
    if (_tab == index) return;
    _tab = index;
    notifyListeners();
  }
}
