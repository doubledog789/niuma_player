import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

/// 简单的 PlayerBackend mock，专门给 PiP 测试用。
/// 不复用 state_machine_test 的 FakePlayerBackend——那个是为状态机
/// 行为设计的，本测试只关心 PiP method dispatch + 闸门逻辑。
class _PipFakeBackend implements PlayerBackend {
  _PipFakeBackend({
    this.enterPipResult = false,
    this.exitPipResult = false,
  });

  bool enterPipResult;
  bool exitPipResult;

  int enterPipCalled = 0;
  int exitPipCalled = 0;
  int? lastAspectNum;
  int? lastAspectDen;

  final _valueCtrl = StreamController<NiumaPlayerValue>.broadcast(sync: true);
  final _eventCtrl = StreamController<NiumaPlayerEvent>.broadcast(sync: true);
  NiumaPlayerValue _value = NiumaPlayerValue.uninitialized();

  @override
  PlayerBackendKind get kind => PlayerBackendKind.videoPlayer;

  @override
  int? get textureId => null;

  @override
  NiumaPlayerValue get value => _value;

  @override
  Stream<NiumaPlayerValue> get valueStream => _valueCtrl.stream;

  @override
  Stream<NiumaPlayerEvent> get eventStream => _eventCtrl.stream;

  void simulateInitialized({Size size = const Size(1920, 1080)}) {
    _value = NiumaPlayerValue(
      phase: PlayerPhase.ready,
      position: Duration.zero,
      duration: const Duration(seconds: 10),
      size: size,
      bufferedPosition: Duration.zero,
    );
    _valueCtrl.add(_value);
  }

  @override
  Future<void> initialize() async {
    simulateInitialized();
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<bool> enterPictureInPicture({
    required int aspectNum,
    required int aspectDen,
  }) async {
    enterPipCalled++;
    lastAspectNum = aspectNum;
    lastAspectDen = aspectDen;
    return enterPipResult;
  }

  @override
  Future<bool> exitPictureInPicture() async {
    exitPipCalled++;
    return exitPipResult;
  }

  @override
  Future<bool> queryPictureInPictureSupport() async => false;

  /// 测试用：记录最近一次推到 native PiP 的 isPlaying 状态。
  bool? lastPipActionsIsPlaying;
  int updatePipActionsCalled = 0;

  @override
  Future<void> updatePictureInPictureActions({
    required bool isPlaying,
  }) async {
    updatePipActionsCalled++;
    lastPipActionsIsPlaying = isPlaying;
  }

  @override
  Future<double> getBrightness() async => 0.0;
  @override
  Future<bool> setBrightness(double value) async => false;
  @override
  Future<double> getSystemVolume() async => 0.0;
  @override
  Future<bool> setSystemVolume(double value) async => false;

  @override
  Future<void> dispose() async {
    await _valueCtrl.close();
    await _eventCtrl.close();
  }
}

class _PipFakeFactory implements BackendFactory {
  _PipFakeFactory(this.backend);
  final _PipFakeBackend backend;
  @override
  PlayerBackend createVideoPlayer(NiumaDataSource ds) => backend;
  @override
  PlayerBackend createNative(NiumaDataSource ds, {required bool forceIjk}) =>
      backend;
}

NiumaPlayerController _makeController(_PipFakeBackend backend) {
  return NiumaPlayerController.dataSource(
    NiumaDataSource.network('https://example.com/test.mp4'),
    backendFactory: _PipFakeFactory(backend),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NiumaPlayerController danmakuVisibility', () {
    test('danmakuVisibility ValueNotifier 默认 true', () {
      final backend = _PipFakeBackend();
      final ctl = _makeController(backend);
      expect(ctl.danmakuVisibility, isA<ValueNotifier<bool>>());
      expect(ctl.danmakuVisibility.value, isTrue);
      ctl.dispose();
    });

    test('danmakuVisibility 可被外部更新并触发 listener', () {
      final backend = _PipFakeBackend();
      final ctl = _makeController(backend);
      bool? heard;
      ctl.danmakuVisibility.addListener(
        () => heard = ctl.danmakuVisibility.value,
      );
      ctl.danmakuVisibility.value = false;
      expect(heard, isFalse);
      ctl.dispose();
    });
  });

  group('NiumaPlayerController PiP', () {
    test('enterPictureInPicture 在未 initialize 时返 false 不调 backend', () async {
      final backend = _PipFakeBackend(enterPipResult: true);
      final c = _makeController(backend);
      // 不调 initialize → value.isInitialized=false
      final r = await c.enterPictureInPicture();
      expect(r, isFalse);
      expect(backend.enterPipCalled, 0);
      await c.dispose();
    });

    test('enterPictureInPicture initialize 后调 backend 并传 aspect', () async {
      final backend = _PipFakeBackend(enterPipResult: true);
      final c = _makeController(backend);
      await c.initialize();
      // initialize 后 value.size = 1920x1080 → aspect 16:9
      final r = await c.enterPictureInPicture();
      expect(r, isTrue);
      expect(backend.enterPipCalled, 1);
      expect(backend.lastAspectNum, isPositive);
      expect(backend.lastAspectDen, isPositive);
      // 16:9 约分后应 16/9 或近似（1920*1000=1920000, 1080*1000=1080000, gcd=120000 → 16/9）
      final ratio = backend.lastAspectNum! / backend.lastAspectDen!;
      expect(ratio, closeTo(16 / 9, 0.01));
      await c.dispose();
    });

    test('enterPictureInPicture 调 backend 之前先把 value 乐观翻成 inPip=true',
        () async {
      // 防 Android PiP 转场时 NiumaControlBar 在迷你窗里渲染一帧 overflow。
      final backend = _PipFakeBackend(enterPipResult: true);
      final c = _makeController(backend);
      await c.initialize();
      expect(c.value.isInPictureInPicture, isFalse);
      final f = c.enterPictureInPicture();
      // 还没 await——value 应该已经被乐观翻成 true（同步先于 backend 调用前发生）。
      expect(c.value.isInPictureInPicture, isTrue,
          reason: 'enterPictureInPicture 调 backend 前已乐观翻 value');
      await f;
      expect(c.value.isInPictureInPicture, isTrue);
      await c.dispose();
    });

    test('enterPictureInPicture 失败时 value 回滚到 inPip=false', () async {
      final backend = _PipFakeBackend(enterPipResult: false);
      final c = _makeController(backend);
      await c.initialize();
      final r = await c.enterPictureInPicture();
      expect(r, isFalse);
      expect(c.value.isInPictureInPicture, isFalse,
          reason: 'backend 返 false 应该回滚 value');
      await c.dispose();
    });

    test('enterPictureInPicture 已在 PiP → 返 false 不重入', () async {
      final backend = _PipFakeBackend(enterPipResult: true);
      final c = _makeController(backend);
      await c.initialize();
      // 模拟已在 PiP（直接改 value）
      c.value = c.value.copyWith(isInPictureInPicture: true);
      final r = await c.enterPictureInPicture();
      expect(r, isFalse);
      expect(backend.enterPipCalled, 0, reason: '已在 PiP 时不应再调 backend');
      await c.dispose();
    });

    test('PiP 中 phase 翻 playing↔paused 会推 updatePictureInPictureActions',
        () async {
      final backend = _PipFakeBackend(enterPipResult: true);
      final c = _makeController(backend);
      await c.initialize();
      // 进 PiP——乐观更新立刻把 inPip=true 写进 value，但此时 phase=ready
      // 不是 playing，所以推 isPlaying=false。
      await c.enterPictureInPicture();
      expect(backend.lastPipActionsIsPlaying, isFalse);
      final initialCount = backend.updatePipActionsCalled;

      // 模拟 backend 推 phase=playing（用户点了 PiP 窗里的 play 按钮）。
      c.value = c.value.copyWith(phase: PlayerPhase.playing);
      expect(backend.lastPipActionsIsPlaying, isTrue);
      expect(backend.updatePipActionsCalled, initialCount + 1);

      // 翻回 paused → 推 isPlaying=false。
      c.value = c.value.copyWith(phase: PlayerPhase.paused);
      expect(backend.lastPipActionsIsPlaying, isFalse);
      expect(backend.updatePipActionsCalled, initialCount + 2);

      // position 更新（playing 不变）→ 不应再调（去重边沿）。
      c.value = c.value.copyWith(position: const Duration(seconds: 5));
      expect(backend.updatePipActionsCalled, initialCount + 2);

      await c.dispose();
    });

    test('退出 PiP 后 phase 翻不再推 updatePictureInPictureActions', () async {
      final backend = _PipFakeBackend(enterPipResult: true);
      final c = _makeController(backend);
      await c.initialize();
      await c.enterPictureInPicture();
      // 模拟系统 PiP 关闭。
      c.value = c.value.copyWith(isInPictureInPicture: false);
      final countAfterExit = backend.updatePipActionsCalled;
      // 退出后 play/pause 不再推到 native PiP（控件已不可见）。
      c.value = c.value.copyWith(phase: PlayerPhase.playing);
      c.value = c.value.copyWith(phase: PlayerPhase.paused);
      expect(backend.updatePipActionsCalled, countAfterExit);

      await c.dispose();
    });

    test('exitPictureInPicture 不在 PiP 返 false 不调 backend', () async {
      final backend = _PipFakeBackend(exitPipResult: true);
      final c = _makeController(backend);
      await c.initialize();
      final r = await c.exitPictureInPicture();
      expect(r, isFalse);
      expect(backend.exitPipCalled, 0);
      await c.dispose();
    });

    test('exitPictureInPicture 在 PiP 调 backend', () async {
      final backend = _PipFakeBackend(exitPipResult: true);
      final c = _makeController(backend);
      await c.initialize();
      c.value = c.value.copyWith(isInPictureInPicture: true);
      final r = await c.exitPictureInPicture();
      expect(r, isTrue);
      expect(backend.exitPipCalled, 1);
      await c.dispose();
    });

    test('autoEnterPictureInPictureOnBackground setter 同值短路', () async {
      final backend = _PipFakeBackend();
      final c = _makeController(backend);
      expect(c.autoEnterPictureInPictureOnBackground, isFalse);
      c.autoEnterPictureInPictureOnBackground = false; // no-op
      c.autoEnterPictureInPictureOnBackground = true;
      expect(c.autoEnterPictureInPictureOnBackground, isTrue);
      c.autoEnterPictureInPictureOnBackground = true; // no-op
      c.autoEnterPictureInPictureOnBackground = false;
      expect(c.autoEnterPictureInPictureOnBackground, isFalse);
      await c.dispose();
    });

    test('autoEnter=true → 注册 WidgetsBindingObserver；false → 摘除', () async {
      final backend = _PipFakeBackend(enterPipResult: true);
      final c = _makeController(backend);
      await c.initialize();

      // 模拟 phase=playing + 不在 PiP
      c.value = c.value.copyWith(phase: PlayerPhase.playing);

      // 通过 binding 广播 lifecycle，验证 observer 注册/摘除效果
      final binding = WidgetsBinding.instance;

      // false → false（默认）：不挂 observer，inactive 不触发
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(backend.enterPipCalled, 0, reason: 'autoEnter=false 时不应触发');

      // 开 autoEnter
      c.autoEnterPictureInPictureOnBackground = true;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(backend.enterPipCalled, 1,
          reason: 'autoEnter=true + playing + !inPip → 触发一次');

      // 关 autoEnter
      c.autoEnterPictureInPictureOnBackground = false;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(backend.enterPipCalled, 1,
          reason: 'autoEnter=false 后 observer 已摘除，不应再触发');

      await c.dispose();
    });
  });
}
