// 屏幕常亮（wakelock）边沿测试：playing 上升沿开、下降沿关、多实例进程级
// 计数归并、dispose 释放、manageScreenWakelock=false 不碰。
//
// 独立文件：进程级计数 `_wakelockHolderCount` 是 library top-level 状态，
// flutter test 每个文件独立 isolate，互不污染。
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

class _RecordingBridge implements PlatformBridge {
  @override
  bool get isIOS => false;
  @override
  bool get isWeb => false;
  @override
  Future<String> deviceFingerprint() async => 'test';
  @override
  Future<int> processHeapLimitMb() async => 256;

  final List<bool> calls = <bool>[];

  @override
  Future<void> setKeepScreenOn(bool on) async {
    calls.add(on);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final src = NiumaMediaSource.single(
    NiumaDataSource.network('https://example.com/a.mp4'),
  );

  NiumaPlayerValue playing(NiumaPlayerValue v) =>
      v.copyWith(phase: PlayerPhase.playing);
  NiumaPlayerValue paused(NiumaPlayerValue v) =>
      v.copyWith(phase: PlayerPhase.paused);

  test('playing 上升沿开亮屏，暂停下降沿释放', () async {
    final bridge = _RecordingBridge();
    final c = NiumaPlayerController(src, platform: bridge);
    c.value = playing(c.value);
    expect(bridge.calls, [true]);
    c.value = paused(c.value);
    expect(bridge.calls, [true, false]);
    await c.dispose();
    expect(bridge.calls, [true, false], reason: '已释放过，dispose 不重复调');
  });

  test('多实例归并：任一在播保持亮屏，全部停了才释放', () async {
    final bridge = _RecordingBridge();
    final a = NiumaPlayerController(src, platform: bridge);
    final b = NiumaPlayerController(src, platform: bridge);
    a.value = playing(a.value);
    b.value = playing(b.value);
    expect(bridge.calls, [true], reason: '第二个在播不重复开');
    a.value = paused(a.value);
    expect(bridge.calls, [true], reason: 'b 还在播，不能关');
    b.value = paused(b.value);
    expect(bridge.calls, [true, false]);
    await a.dispose();
    await b.dispose();
  });

  test('在播时直接 dispose 也释放计数', () async {
    final bridge = _RecordingBridge();
    final c = NiumaPlayerController(src, platform: bridge);
    c.value = playing(c.value);
    expect(bridge.calls, [true]);
    await c.dispose();
    expect(bridge.calls, [true, false]);
  });

  test('manageScreenWakelock=false 完全不碰亮屏', () async {
    final bridge = _RecordingBridge();
    final c = NiumaPlayerController(
      src,
      platform: bridge,
      options: const NiumaPlayerOptions(manageScreenWakelock: false),
    );
    c.value = playing(c.value);
    c.value = paused(c.value);
    await c.dispose();
    expect(bridge.calls, isEmpty);
  });
}
