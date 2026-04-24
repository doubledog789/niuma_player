import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'niuma_player_method_channel.dart';

abstract class NiumaPlayerPlatform extends PlatformInterface {
  /// Constructs a NiumaPlayerPlatform.
  NiumaPlayerPlatform() : super(token: _token);

  static final Object _token = Object();

  static NiumaPlayerPlatform _instance = MethodChannelNiumaPlayer();

  /// The default instance of [NiumaPlayerPlatform] to use.
  ///
  /// Defaults to [MethodChannelNiumaPlayer].
  static NiumaPlayerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [NiumaPlayerPlatform] when
  /// they register themselves.
  static set instance(NiumaPlayerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
