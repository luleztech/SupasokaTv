import 'package:supasoka/models/remote_player_config.dart';

/// Default player policy (EaMax reads this from remote config; Supasoka uses sane defaults).
class PlayerConfigService {
  PlayerConfigService._();

  static RemotePlayerConfig get playerConfig => RemotePlayerConfig.fromJson(const {});

  static Future<void> syncFromServer() async {
    // Supasoka playback API does not ship a playerConfig bundle yet.
  }
}
