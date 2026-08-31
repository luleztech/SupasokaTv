import 'package:flutter/foundation.dart';

/// Viewer quality cap for media_kit multi-track streams.
class TvPlaybackSettings extends ChangeNotifier {
  TvPlaybackSettings({this.qualityLabel = '480p'});

  static const options = ['Auto', '480p', '720p', '1080p'];

  String qualityLabel;

  int? get maxHeight {
    switch (qualityLabel.toLowerCase()) {
      case '480p':
        return 480;
      case '720p':
        return 720;
      case '1080p':
        return 1080;
      default:
        return null;
    }
  }

  void setQuality(String label) {
    if (!options.contains(label) || label == qualityLabel) return;
    qualityLabel = label;
    notifyListeners();
  }
}

bool tvPlatformSupportsWebView() {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    default:
      return false;
  }
}
