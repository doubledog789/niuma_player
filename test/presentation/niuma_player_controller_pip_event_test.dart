import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

class _PipEmittingFakeBackend implements PlayerBackend {
  final _valueCtrl = StreamController<NiumaPlayerValue>.broadcast(sync: true);
  final _eventCtrl = StreamController<NiumaPlayerEvent>.broadcast(sync: true);
  NiumaPlayerValue _value = NiumaPlayerValue.uninitialized();

  int playCalled = 0;
  int pauseCalled = 0;

  void emit(NiumaPlayerEvent event) {
    _eventCtrl.add(event);
  }

  void simulateValue(NiumaPlayerValue v) {
    _value = v;
    _valueCtrl.add(_value);
  }

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

  @override
  Future<void> initialize() async {
    _value = NiumaPlayerValue(
      phase: PlayerPhase.ready,
      position: Duration.zero,
      duration: const Duration(seconds: 10),
      size: const Size(1920, 1080),
      bufferedPosition: Duration.zero,
    );
    _valueCtrl.add(_value);
  }

  @override
  Future<void> play() async => playCalled++;
  @override
  Future<void> pause() async => pauseCalled++;
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
  }) async =>
      false;
  @override
  Future<bool> exitPictureInPicture() async => false;
  @override
  Future<bool> queryPictureInPictureSupport() async => false;
  @override
  Future<void> dispose() async {
    await _valueCtrl.close();
    await _eventCtrl.close();
  }
}

class _PipEmittingFakeFactory implements BackendFactory {
  _PipEmittingFakeFactory(this.backend);
  final _PipEmittingFakeBackend backend;
  @override
  PlayerBackend createVideoPlayer(NiumaDataSource ds) => backend;
  @override
  PlayerBackend createNative(NiumaDataSource ds, {required bool forceIjk}) =>
      backend;
}

NiumaPlayerController _makeController(_PipEmittingFakeBackend backend) {
  return NiumaPlayerController.dataSource(
    NiumaDataSource.network('https://example.com/test.mp4'),
    backendFactory: _PipEmittingFakeFactory(backend),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PiP EventChannel → Controller value 同步', () {
    test('PipModeChanged(true) → value.isInPictureInPicture = true', () async {
      final backend = _PipEmittingFakeBackend();
      final c = _makeController(backend);
      await c.initialize();
      expect(c.value.isInPictureInPicture, isFalse);
      backend.emit(const PipModeChanged(isInPip: true));
      // 等 controller 处理事件
      await Future<void>.delayed(Duration.zero);
      expect(c.value.isInPictureInPicture, isTrue);
      await c.dispose();
    });

    test('PipModeChanged(false) → value.isInPictureInPicture = false',
        () async {
      final backend = _PipEmittingFakeBackend();
      final c = _makeController(backend);
      await c.initialize();
      c.value = c.value.copyWith(isInPictureInPicture: true);
      backend.emit(const PipModeChanged(isInPip: false));
      await Future<void>.delayed(Duration.zero);
      expect(c.value.isInPictureInPicture, isFalse);
      await c.dispose();
    });

    test('PipRemoteAction(playPauseToggle) playing → 调 pause', () async {
      final backend = _PipEmittingFakeBackend();
      final c = _makeController(backend);
      await c.initialize();
      backend.simulateValue(c.value.copyWith(phase: PlayerPhase.playing));
      backend.emit(const PipRemoteAction(action: 'playPauseToggle'));
      await Future<void>.delayed(Duration.zero);
      expect(backend.pauseCalled, 1);
      await c.dispose();
    });

    test('PipRemoteAction(playPauseToggle) paused → 调 play', () async {
      final backend = _PipEmittingFakeBackend();
      final c = _makeController(backend);
      await c.initialize();
      backend.simulateValue(c.value.copyWith(phase: PlayerPhase.paused));
      backend.emit(const PipRemoteAction(action: 'playPauseToggle'));
      await Future<void>.delayed(Duration.zero);
      expect(backend.playCalled, 1);
      await c.dispose();
    });
  });
}
