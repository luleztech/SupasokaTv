import 'dart:async';

/// Playback analytics — no-op in Supasoka (EaMax posts to /api/v2/analytics/playback).
class PlaybackAnalytics {
  PlaybackAnalytics._();

  static Future<void> trackChannelOpen({
    required int channelId,
    required String channelName,
    required String engine,
  }) async {}

  static Future<void> trackStreamFailure({
    required int channelId,
    required String reason,
    int? failoverStep,
  }) async {}
}
