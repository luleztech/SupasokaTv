class RemotePlayerConfig {
  const RemotePlayerConfig({
    required this.preferredEngine,
    required this.bufferMinMs,
    required this.bufferMaxMs,
    required this.initialBufferMs,
    required this.retryMax,
    required this.retryDelayMs,
    required this.reconnectEnabled,
    required this.autoPlay,
    required this.defaultQuality,
    required this.failoverToWebview,
    required this.hardwareAcceleration,
    required this.softwareDecodeFallback,
    required this.backgroundPlayback,
    required this.resumePlayback,
    required this.networkTimeoutMs,
    required this.reconnectionPolicy,
    required this.qualitiesAllowed,
    required this.languagesAllowed,
  });

  final String preferredEngine;
  final int bufferMinMs;
  final int bufferMaxMs;
  final int initialBufferMs;
  final int retryMax;
  final int retryDelayMs;
  final bool reconnectEnabled;
  final bool autoPlay;
  final String defaultQuality;
  final bool failoverToWebview;
  final bool hardwareAcceleration;
  final bool softwareDecodeFallback;
  final bool backgroundPlayback;
  final bool resumePlayback;
  final int networkTimeoutMs;
  final String reconnectionPolicy;
  final List<String> qualitiesAllowed;
  final List<String> languagesAllowed;

  factory RemotePlayerConfig.fromJson(Map<String, dynamic> json) {
    final qualities = json['qualitiesAllowed'];
    final languages = json['languagesAllowed'];
    return RemotePlayerConfig(
      preferredEngine: json['preferredEngine']?.toString() ?? 'auto',
      bufferMinMs: int.tryParse('${json['bufferMinMs']}') ?? 800,
      bufferMaxMs: int.tryParse('${json['bufferMaxMs']}') ?? 12000,
      initialBufferMs: int.tryParse('${json['initialBufferMs']}') ?? 1500,
      retryMax: int.tryParse('${json['retryMax']}') ?? 4,
      retryDelayMs: int.tryParse('${json['retryDelayMs']}') ?? 1200,
      reconnectEnabled: json['reconnectEnabled'] != false,
      autoPlay: json['autoPlay'] != false,
      defaultQuality: json['defaultQuality']?.toString() ?? '360p',
      failoverToWebview: json['failoverToWebview'] != false,
      hardwareAcceleration: json['hardwareAcceleration'] != false,
      softwareDecodeFallback: json['softwareDecodeFallback'] != false,
      backgroundPlayback: json['backgroundPlayback'] == true,
      resumePlayback: json['resumePlayback'] != false,
      networkTimeoutMs: int.tryParse('${json['networkTimeoutMs']}') ?? 15000,
      reconnectionPolicy: json['reconnectionPolicy']?.toString() ?? 'balanced',
      qualitiesAllowed: qualities is List
          ? qualities.map((e) => e.toString()).toList()
          : const ['auto', '240p', '360p', '480p', '720p', '1080p'],
      languagesAllowed: languages is List
          ? languages.map((e) => e.toString()).toList()
          : const ['sw', 'en'],
    );
  }
}
