import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

ThemeData adminTheme() {
  const seed = Color(0xFF7c3aed);
  const tertiary = Color(0xFF06b6d4);

  final base = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
    primary: const Color(0xFFa78bfa),
    secondary: const Color(0xFF22d3ee),
    tertiary: tertiary,
    surface: const Color(0xFF12151f),
  );

  final td = ThemeData(
    useMaterial3: true,
    colorScheme: base,
    scaffoldBackgroundColor: const Color(0xFF0a0c10),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      selectedIconTheme: const IconThemeData(color: Colors.white, size: 26),
      unselectedIconTheme: IconThemeData(color: Colors.white.withValues(alpha: 0.45), size: 24),
      selectedLabelTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 11.5,
        letterSpacing: 0.2,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.42),
        fontWeight: FontWeight.w500,
        fontSize: 11,
      ),
      indicatorColor: base.primary.withValues(alpha: 0.28),
      labelType: NavigationRailLabelType.all,
      minWidth: 76,
      minExtendedWidth: 212,
    ),
    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.white.withValues(alpha: 0.06),
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white.withValues(alpha: 0.45),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
      indicatorColor: base.primary.withValues(alpha: 0.35),
      overlayColor: WidgetStatePropertyAll(base.primary.withValues(alpha: 0.08)),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF161a24),
      elevation: 0,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF1a1e2a),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      elevation: 8,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 8,
      backgroundColor: const Color(0xFF2f3548),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      contentTextStyle: const TextStyle(
        color: Color(0xFFfafafa),
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      actionTextColor: const Color(0xFFc4b5fd),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1e2330),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: base.primary.withValues(alpha: 0.85), width: 1.5),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      iconColor: Colors.white70,
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4),
      titleLarge: TextStyle(fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontWeight: FontWeight.w600),
    ),
  );
  return td.copyWith(
    textTheme: td.textTheme.apply(
      decoration: TextDecoration.none,
      decorationColor: Colors.transparent,
    ),
    primaryTextTheme: td.primaryTextTheme.apply(
      decoration: TextDecoration.none,
      decorationColor: Colors.transparent,
    ),
  );
}
