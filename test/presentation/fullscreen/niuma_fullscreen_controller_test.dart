import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/player/niuma_fullscreen_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    debugDefaultTargetPlatformOverride = null;
  });

  List<MethodCall> orientationCalls() => calls
      .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
      .toList();

  test('enter 横屏视频 → 锁 landscape 左右 + isFullscreen=true', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final c = NiumaFullscreenController();
    c.enter(isVerticalVideo: false);
    final args = orientationCalls().single.arguments as List<dynamic>;
    expect(args, contains('DeviceOrientation.landscapeLeft'));
    expect(args, contains('DeviceOrientation.landscapeRight'));
    expect(c.isFullscreen.value, isTrue);
    c.dispose();
  });

  test('enter 竖直视频 → 锁 portrait', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final c = NiumaFullscreenController();
    c.enter(isVerticalVideo: true);
    final args = orientationCalls().single.arguments as List<dynamic>;
    expect(args, <String>['DeviceOrientation.portraitUp']);
    c.dispose();
  });

  test('exit on Android → 第一步立即 portraitUp + isFullscreen=false', () {
    // 第二步（下一帧传空 list 释放锁）是逐字照搬原 widget 的实现细节，
    // 走 SchedulerBinding.addPostFrameCallback，此处只断言立即生效的第一步。
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final c = NiumaFullscreenController();
    c.exit();
    expect(orientationCalls().first.arguments,
        <String>['DeviceOrientation.portraitUp']);
    expect(c.isFullscreen.value, isFalse);
    c.dispose();
  });

  test('exit on iOS → 单步空 list', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final c = NiumaFullscreenController();
    c.exit();
    expect(orientationCalls().single.arguments, <dynamic>[]);
    c.dispose();
  });
}
