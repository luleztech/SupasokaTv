import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences_linux/shared_preferences_linux.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Linux/Windows federated plugins use Dart `registerWith()` — Flutter does not
/// always inject the registrant for nested apps, so call this before SharedPreferences.
Future<void> registerDesktopDartPlugins() async {
  if (kIsWeb) return;

  if (Platform.isLinux) {
    PathProviderLinux.registerWith();
    SharedPreferencesLinux.registerWith();
    PackageInfoPlusLinuxPlugin.registerWith();
    WakelockPlusLinuxPlugin.registerWith();
    return;
  }

  if (Platform.isWindows) {
    PathProviderWindows.registerWith();
    SharedPreferencesWindows.registerWith();
    PackageInfoPlusWindowsPlugin.registerWith();
    WakelockPlusWindowsPlugin.registerWith();
  }
}
