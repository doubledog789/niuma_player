import 'dart:async';
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

/// 可控 + 记录型 fake backend：可直接 emit 带 duration 的 value，并记录
/// seek / 亮度 / 音量调用，用于断言 [NiumaGestureController] 的纯逻辑。
class _RecBackend extends PlayerBackend {
  final StreamController<NiumaPlayerValue> _vc =
      StreamController<NiumaPlayerValue>.broadcast(sync: true);
  final StreamController<NiumaPlayerEvent> _ec =
      StreamController<NiumaPlayerEvent>.broadcast(sync: true);
  NiumaPlayerValue _v = NiumaPlayerValue.uninitialized();

  double brightness = 0.3;
  double volume = 0.4;
  final List<double> brightnessSets = <double>[];
  final List<double> volumeSets = <double>[];
  Duration? lastSeek;

  void emit(NiumaPlayerValue v) {
    _v = v;
    _vc.add(v);
  }

  @override
  PlayerBackendKind get kind => PlayerBackendKind.videoPlayer;
  @override
  int? get textureId => null;
  @override
  NiumaPlayerValue get value => _v;
  @override
  Stream<NiumaPlayerValue> get valueStream => _vc.stream;
  @override
  Stream<NiumaPlayerEvent> get eventStream => _ec.stream;
  @override
  Future<void> initialize() async =>
      emit(_v.copyWith(phase: PlayerPhase.ready));
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async => lastSeek = position;
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> setLooping(bool looping) async {}
  @override
  Future<double> getBrightness() async => brightness;
  @override
  Future<bool> setBrightness(double v) async {
    brightnessSets.add(v);
    brightness = v;
    return true;
  }

  @override
  Future<double> getSystemVolume() async => volume;
  @override
  Future<bool> setSystemVolume(double v) async {
    volumeSets.add(v);
    volume = v;
    return true;
  }

  @override
  Future<void> dispose() async {
    await _vc.close();
    await _ec.close();
  }
}

class _Factory implements BackendFactory {
  _Factory(this.backend);
  final _RecBackend backend;
  @override
  PlayerBackend createVideoPlayer(NiumaDataSource ds) => backend;
  @override
  PlayerBackend createNative(NiumaDataSource ds, {required bool forceIjk, bool useAndroidPlatformView = false}) =>
      backend;
}

class _NoopBridge implements PlatformBridge {
  @override
  bool get isIOS => false;
  @override
  bool get isWeb => false;
  @override
  Future<String> deviceFingerprint() async => 'test';
  @override
  Future<int> processHeapLimitMb() async => 256;
  @override
  Future<void> setKeepScreenOn(bool on) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const size = Size(400, 300);

  Future<(NiumaPlayerController, _RecBackend, NiumaGestureController)>
      build() async {
    final backend = _RecBackend();
    final controller = NiumaPlayerController(
      NiumaMediaSource.single(NiumaDataSource.network('https://x/v.mp4')),
      platform: _NoopBridge(),
      backendFactory: _Factory(backend),
    );
    await controller.initialize();
    // 注入 4 分钟时长 + 当前 1 分钟位置，供 seek 数学用。
    backend.emit(NiumaPlayerValue.uninitialized().copyWith(
      phase: PlayerPhase.playing,
      position: const Duration(minutes: 1),
      duration: const Duration(minutes: 4),
    ));
    return (controller, backend, NiumaGestureController(controller));
  }

  test('水平 pan 过阈值 → 锁定 seek，松手按进度提交 seekTo', () async {
    final (controller, backend, g) = await build();
    g.onPanStart(const Offset(200, 150));
    // dx = +width*0.5 = +200 → delta = 0.5 * 240000 * 0.5 = 60000ms = +60s
    await g.onPanUpdate(const Offset(400, 150), size);
    expect(g.feedback.value?.kind, GestureKind.horizontalSeek);
    g.onPanEnd();
    // seekStart 1min + 60s = 2min。
    expect(backend.lastSeek, const Duration(minutes: 2));
    await controller.dispose();
  });

  test('左半屏垂直 pan → 锁定亮度并记录 setBrightness', () async {
    final (controller, backend, g) = await build();
    g.onPanStart(const Offset(50, 150)); // 左半屏
    await g.onPanUpdate(const Offset(50, 30), size); // 上滑 → 亮度增
    expect(g.feedback.value?.kind, GestureKind.brightness);
    expect(backend.brightnessSets, isNotEmpty);
    expect(backend.brightnessSets.last, greaterThan(0.3));
    await controller.dispose();
  });

  test('右半屏垂直 pan → 锁定音量并记录 setSystemVolume', () async {
    final (controller, backend, g) = await build();
    g.onPanStart(const Offset(350, 150)); // 右半屏
    await g.onPanUpdate(const Offset(350, 30), size); // 上滑 → 音量增
    expect(g.feedback.value?.kind, GestureKind.volume);
    expect(backend.volumeSets, isNotEmpty);
    expect(backend.volumeSets.last, greaterThan(0.4));
    await controller.dispose();
  });

  test('双击播放中 → 暂停 + HUD 用语义 hudIcon 不引 material icon / 资源路径', () async {
    final (controller, backend, g) = await build();
    g.onDoubleTap();
    final hud = g.feedback.value;
    expect(hud?.kind, GestureKind.doubleTap);
    expect(hud?.hudIcon, GestureHudIcon.pause);
    await controller.dispose();
  });

  test('disabledGestures 命中 → 双击不触发、无 HUD', () async {
    final backend = _RecBackend();
    final controller = NiumaPlayerController(
      NiumaMediaSource.single(NiumaDataSource.network('https://x/v.mp4')),
      platform: _NoopBridge(),
      backendFactory: _Factory(backend),
    );
    await controller.initialize();
    final g = NiumaGestureController(
      controller,
      disabledGestures: const {GestureKind.doubleTap},
    );
    g.onDoubleTap();
    expect(g.feedback.value, isNull);
    await controller.dispose();
  });
}
