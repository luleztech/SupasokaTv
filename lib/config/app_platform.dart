import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Build-time variant: `mobile` (default), `tv`, or `desktop`.
/// TV builds pass `--dart-define=SUPASOKA_VARIANT=tv`.
const _variantRaw = String.fromEnvironment('SUPASOKA_VARIANT', defaultValue: 'mobile');

/// Shared platform / form-factor helpers for phone, Android TV, and desktop.
abstract final class AppPlatform {
  static String get variant => _variantRaw;

  static bool get isTv => _variantRaw == 'tv';

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool get isMobileAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android && !isTv;

  /// Side rail navigation works better on TV remotes and wide desktop windows.
  static bool get useSideNavigation => isTv || isDesktop;

  /// 10-foot UI scale for Android TV.
  static double get uiScale => isTv ? 1.22 : 1.0;

  static double get homeRailTileWidth => isTv ? 240 : (isDesktop ? 200 : 180);

  static double get homeRailPosterHeight => isTv ? 290 : (isDesktop ? 240 : 220);

  /// Mobile money USSD/STK is phone-only; TV shows instructions instead.
  static bool get supportsInAppPayments => !isTv;

  static String get appDisplayName =>
      isTv ? 'Supasoka TV' : (isDesktop ? 'Supasoka' : 'Supasoka');

  static String get platformLabel {
    if (kIsWeb) return 'web';
    if (isTv) return 'android_tv';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return defaultTargetPlatform.name;
  }
}
