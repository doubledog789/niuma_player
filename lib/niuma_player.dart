
import 'niuma_player_platform_interface.dart';

class NiumaPlayer {
  Future<String?> getPlatformVersion() {
    return NiumaPlayerPlatform.instance.getPlatformVersion();
  }
}
