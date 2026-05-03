import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opens the Kotlin [SupasokaNativePlayerActivity] / PlayerManager stack on Android.
class NativeAndroidPlayer {
  NativeAndroidPlayer._();

  static const _channel = MethodChannel('com.ayubu.supasoka/native_player');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> open({
    required String url,
    String licenseUrl = '',
    String token = '',
    String drmType = 'NONE',
    String clearKeyHex = '',
    Map<String, String>? headers,
  }) async {
    if (!supported) return;
    await _channel.invokeMethod<void>('open', <String, dynamic>{
      'url': url,
      'licenseUrl': licenseUrl,
      'token': token,
      'drmType': drmType,
      'clearKeyHex': clearKeyHex,
      'headersJson': headers == null || headers.isEmpty ? '' : jsonEncode(headers),
    });
  }
}
