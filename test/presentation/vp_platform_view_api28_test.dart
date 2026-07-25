// Android 9（API 28）上 video_player 的平台视图走 setupSurfaceWithCallback：
// surfaceCreated 里 seekTo(1)、surfaceDestroyed 里无条件 setVideoSurface(null)
// （不判断当前绑的是不是自己）。多 surface 交接（全屏 ↔ inline）必然黑屏 +
// 跳回开头，故 vp 主路径在 API 28 降级 textureView。
// IJK 路径走自家 PlayerSession.surfaceStack，不受此限。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

import '../state_machine_test.dart' show FakePlayerBackend, FakePlatformBridge;

class _RecordingFactory implements BackendFactory {
  final List<bool> vpFlags = <bool>[];
  final List<bool> nativeFlags = <bool>[];

  @override
  PlayerBackend createVideoPlayer(
    NiumaDataSource ds, {
    bool useAndroidPlatformView = false,
  }) {
    vpFlags.add(useAndroidPlatformView);
    return FakePlayerBackend(kind: PlayerBackendKind.videoPlayer);
  }

  @override
  PlayerBackend createNative(
    NiumaDataSource ds, {
    bool useAndroidPlatformView = false,
  }) {
    nativeFlags.add(useAndroidPlatformView);
    return FakePlayerBackend(kind: PlayerBackendKind.native);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('niuma_player/system');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  var sdkIntCalls = 0;

  void mockSdkInt(int value) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'getAndroidSdkInt') return null;
      sdkIntCalls++;
      return value;
    });
  }

  setUp(() {
    sdkIntCalls = 0;
    NiumaCapabilities.debugResetCaches();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    NiumaCapabilities.debugResetCaches();
  });

  Future<_RecordingFactory> runInit({required bool platformView}) async {
    final factory = _RecordingFactory();
    final controller = NiumaPlayerController.dataSource(
      NiumaDataSource.network('https://example.com/a.mp4'),
      options: NiumaPlayerOptions(useAndroidPlatformView: platformView),
      platform: FakePlatformBridge(),
      backendFactory: factory,
    );
    await controller.initialize();
    await controller.dispose();
    return factory;
  }

  test('API 28 → vp 路径降级 textureView', () async {
    mockSdkInt(28);
    final factory = await runInit(platformView: true);
    expect(factory.vpFlags, <bool>[false]);
  });

  test('API 29+ → vp 路径保持 platformView', () async {
    mockSdkInt(33);
    final factory = await runInit(platformView: true);
    expect(factory.vpFlags, <bool>[true]);
  });

  test('useAndroidPlatformView=false 时不查 sdkInt', () async {
    mockSdkInt(28);
    final factory = await runInit(platformView: false);
    expect(factory.vpFlags, <bool>[false]);
    expect(sdkIntCalls, 0, reason: '关着的开关不该白跑一次 channel');
  });

  test('sdkInt 查询结果进程内缓存', () async {
    mockSdkInt(33);
    await runInit(platformView: true);
    await runInit(platformView: true);
    expect(sdkIntCalls, 1);
  });

  test('channel 缺失时按非 28 处理，不误伤其它版本', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final factory = await runInit(platformView: true);
    expect(factory.vpFlags, <bool>[true]);
  });
}
