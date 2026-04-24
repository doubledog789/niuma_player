import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'niuma_player_platform_interface.dart';

/// An implementation of [NiumaPlayerPlatform] that uses method channels.
class MethodChannelNiumaPlayer extends NiumaPlayerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('niuma_player');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
