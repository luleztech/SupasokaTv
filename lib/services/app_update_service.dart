import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

const kDefaultPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.ayubu.supasoka';

class AppUpdateStatus {
  const AppUpdateStatus({
    required this.required,
    required this.currentVersion,
    required this.currentBuild,
    required this.minVersion,
    required this.latestVersion,
    required this.minBuild,
    required this.latestBuild,
    required this.playStoreUrl,
  });

  final bool required;
  final String currentVersion;
  final int currentBuild;
  final String minVersion;
  final String latestVersion;
  final int minBuild;
  final int latestBuild;
  final String playStoreUrl;

  factory AppUpdateStatus.upToDate({
    required String currentVersion,
    required int currentBuild,
    required String playStoreUrl,
  }) {
    return AppUpdateStatus(
      required: false,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      minVersion: '',
      latestVersion: '',
      minBuild: 0,
      latestBuild: 0,
      playStoreUrl: playStoreUrl,
    );
  }
}

int _parseVersionParts(String raw) {
  final cleaned = raw.trim().toLowerCase().replaceAll(RegExp(r'^v'), '');
  final parts = cleaned.split('.');
  var score = 0;
  for (var i = 0; i < parts.length && i < 3; i++) {
    final n = int.tryParse(parts[i].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    score = score * 1000 + n.clamp(0, 999);
  }
  return score;
}

bool _isVersionBelow(String current, String minimum) {
  if (minimum.trim().isEmpty) return false;
  return _parseVersionParts(current) < _parseVersionParts(minimum);
}

Map<String, dynamic>? _readAppUpdateMap(Map<String, dynamic> j) {
  final nested = j['appUpdate'];
  if (nested is Map<String, dynamic>) return nested;
  if (nested is Map) return Map<String, dynamic>.from(nested);
  return null;
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

/// Uses server-computed [updateRequired] when present; falls back locally for old APIs.
Future<AppUpdateStatus> evaluateAppUpdateFromConfig(Map<String, dynamic> j) async {
  final info = await PackageInfo.fromPlatform();
  final currentVersion = info.version;
  final currentBuild = int.tryParse(info.buildNumber) ?? 0;
  final appUpdate = _readAppUpdateMap(j);

  final minVersion = (j['minVersion'] as String?)?.trim().isNotEmpty == true
      ? (j['minVersion'] as String).trim()
      : (appUpdate?['minVersion'] as String?)?.trim() ??
          (j['minAndroidVersion'] as String?)?.trim() ??
          '';
  final latestVersion = (j['latestVersion'] as String?)?.trim().isNotEmpty == true
      ? (j['latestVersion'] as String).trim()
      : (appUpdate?['latestVersion'] as String?)?.trim() ?? minVersion;
  final minBuild = _asInt(appUpdate?['minBuild'] ?? j['minAndroidBuild']);
  final latestBuild = _asInt(appUpdate?['latestBuild'] ?? minBuild);
  final playStoreUrl = (appUpdate?['playStoreUrl'] as String?)?.trim().isNotEmpty == true
      ? (appUpdate!['playStoreUrl'] as String).trim()
      : (j['playStoreUrl'] as String?)?.trim().isNotEmpty == true
          ? (j['playStoreUrl'] as String).trim()
          : kDefaultPlayStoreUrl;

  if (kIsWeb || !Platform.isAndroid) {
    return AppUpdateStatus.upToDate(
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      playStoreUrl: playStoreUrl,
    );
  }

  final serverRequired = j['updateRequired'] == true || appUpdate?['updateRequired'] == true;
  if (j.containsKey('updateRequired') || (appUpdate?.containsKey('updateRequired') ?? false)) {
    return AppUpdateStatus(
      required: serverRequired,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      minVersion: minVersion,
      latestVersion: latestVersion,
      minBuild: minBuild,
      latestBuild: latestBuild > 0 ? latestBuild : minBuild,
      playStoreUrl: playStoreUrl,
    );
  }

  final buildRequired = minBuild > 0 && currentBuild < minBuild;
  final versionRequired =
      minBuild <= 0 && minVersion.isNotEmpty && _isVersionBelow(currentVersion, minVersion);

  return AppUpdateStatus(
    required: buildRequired || versionRequired,
    currentVersion: currentVersion,
    currentBuild: currentBuild,
    minVersion: minVersion,
    latestVersion: latestVersion.isNotEmpty ? latestVersion : minVersion,
    minBuild: minBuild,
    latestBuild: latestBuild > 0 ? latestBuild : minBuild,
    playStoreUrl: playStoreUrl,
  );
}

/// Fallbacks when [PackageInfo] omits build on desktop (Linux needs `appBuild` for catalog).
const kPackageVersionFallback = '1.2.7';
const kPackageBuildFallback = '22';

Future<Map<String, String>> appVersionQueryParams() async {
  final info = await PackageInfo.fromPlatform();
  final version = info.version.trim().isNotEmpty ? info.version.trim() : kPackageVersionFallback;
  final rawBuild = info.buildNumber.trim();
  final build = rawBuild.isNotEmpty && rawBuild != '0' ? rawBuild : kPackageBuildFallback;
  return {
    'appBuild': build,
    'appVersion': version,
  };
}

/// Headers sent with protected API calls (playback, payments, config).
Future<Map<String, String>> appVersionHeaders() async {
  final params = await appVersionQueryParams();
  return {
    'X-App-Build': params['appBuild'] ?? '',
    'X-App-Version': params['appVersion'] ?? '',
    'X-Supasoka-Build': params['appBuild'] ?? '',
    'X-Supasoka-Version': params['appVersion'] ?? '',
  };
}
