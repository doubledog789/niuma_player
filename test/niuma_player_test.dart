import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/niuma_player_platform_interface.dart';
import 'package:niuma_player/niuma_player_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockNiumaPlayerPlatform
    with MockPlatformInterfaceMixin
    implements NiumaPlayerPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final NiumaPlayerPlatform initialPlatform = NiumaPlayerPlatform.instance;

  test('$MethodChannelNiumaPlayer is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelNiumaPlayer>());
  });

  test('getPlatformVersion', () async {
    NiumaPlayer niumaPlayerPlugin = NiumaPlayer();
    MockNiumaPlayerPlatform fakePlatform = MockNiumaPlayerPlatform();
    NiumaPlayerPlatform.instance = fakePlatform;

    expect(await niumaPlayerPlugin.getPlatformVersion(), '42');
  });
}
