import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

import 'helpers/fake_device_memory_channel.dart';

/// Simple controllable fake. Tests provide [initFuture] to drive the
/// "Try-Once-Then-Retry" state machine in [NiumaPlayerController].
class FakePlayerBackend implements PlayerBackend {
  FakePlayerBackend({
    required this.kind,
    this.initBlock,
  });

  @override
  final PlayerBackendKind kind;

  /// If non-null, [initialize] invokes this and awaits its result. Lazy
  /// (a `Function`) rather than a bare `Future` so an "errors immediately"
  /// case doesn't fire as an unhandled async error before the controller
  /// has had a chance to attach a listener via [initialize]'s await.
  final Future<void> Function()? initBlock;

  final StreamController<NiumaPlayerValue> _valueController =
      StreamController<NiumaPlayerValue>.broadcast();
  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast();

  NiumaPlayerValue _value = NiumaPlayerValue.uninitialized();

  bool initializeCalled = false;
  bool disposed = false;

  @override
  int? get textureId => kind == PlayerBackendKind.native ? 42 : null;

  @override
  NiumaPlayerValue get value => _value;

  @override
  Stream<NiumaPlayerValue> get valueStream => _valueController.stream;

  @override
  Stream<NiumaPlayerEvent> get eventStream => _eventController.stream;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
    if (initBlock != null) {
      await initBlock!();
    }
    _value = const NiumaPlayerValue(
      phase: PlayerPhase.ready,
      position: Duration.zero,
      duration: Duration(seconds: 10),
      size: Size(1280, 720),
      bufferedPosition: Duration.zero,
    );
    if (!_valueController.isClosed) {
      _valueController.add(_value);
    }
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
  Future<void> dispose() async {
    disposed = true;
    await _valueController.close();
    await _eventController.close();
  }
}

/// Records every [createVideoPlayer] / [createNative] call. Tests can drive
/// a sequence of fake backends (e.g. first one errors, second one succeeds)
/// by giving a `makeNative` that picks a different fake based on its
/// `forceIjk` argument or call index.
class FakeBackendFactory implements BackendFactory {
  FakeBackendFactory({
    required this.makeVideoPlayer,
    required this.makeNative,
  });

  final FakePlayerBackend Function(NiumaDataSource ds) makeVideoPlayer;
  final FakePlayerBackend Function(NiumaDataSource ds, bool forceIjk)
      makeNative;

  final List<FakePlayerBackend> videoPlayers = <FakePlayerBackend>[];
  final List<FakePlayerBackend> nativePlayers = <FakePlayerBackend>[];
  final List<bool> nativeForceIjkArgs = <bool>[];

  @override
  PlayerBackend createVideoPlayer(NiumaDataSource ds) {
    final b = makeVideoPlayer(ds);
    videoPlayers.add(b);
    return b;
  }

  @override
  PlayerBackend createNative(NiumaDataSource ds, {required bool forceIjk}) {
    final b = makeNative(ds, forceIjk);
    nativePlayers.add(b);
    nativeForceIjkArgs.add(forceIjk);
    return b;
  }
}

/// Stubs the host check so tests don't hit `dart:io` Platform / `kIsWeb`.
class FakePlatformBridge implements PlatformBridge {
  FakePlatformBridge({
    this.isIOS = false,
    this.isWeb = false,
    this.fingerprint = 'fake-fp',
  });

  @override
  final bool isIOS;

  @override
  final bool isWeb;

  final String fingerprint;

  @override
  Future<String> deviceFingerprint() async => fingerprint;
}

void main() {
  final ds = NiumaDataSource.network('https://example.com/sample.mp4');

  late FakeDeviceMemoryChannel fakeChannel;

  setUp(() {
    fakeChannel = FakeDeviceMemoryChannel.install();
  });

  tearDown(() {
    fakeChannel.uninstall();
  });

  group('NiumaPlayerController state machine', () {
    test('A. iOS always selects VideoPlayerBackend without touching native',
        () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeNative: (_, __) =>
            FakePlayerBackend(kind: PlayerBackendKind.native),
      );

      final controller = NiumaPlayerController.dataSource(
        ds,
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: factory,
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeBackend, PlayerBackendKind.videoPlayer);
      expect(factory.videoPlayers.length, 1);
      expect(factory.nativePlayers, isEmpty);
      expect(
        events.whereType<BackendSelected>().single,
        isA<BackendSelected>()
            .having((e) => e.kind, 'kind', PlayerBackendKind.videoPlayer)
            .having((e) => e.fromMemory, 'fromMemory', false),
      );

      await sub.cancel();
      await controller.dispose();
    });

    test('B. Web always selects VideoPlayerBackend without touching native',
        () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeNative: (_, __) =>
            FakePlayerBackend(kind: PlayerBackendKind.native),
      );

      final controller = NiumaPlayerController.dataSource(
        ds,
        platform: FakePlatformBridge(isWeb: true),
        backendFactory: factory,
      );

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeBackend, PlayerBackendKind.videoPlayer);
      expect(factory.videoPlayers.length, 1);
      expect(factory.nativePlayers, isEmpty);

      await controller.dispose();
    });

    test('C. Android + forceIjkOnAndroid: true goes straight to native(forceIjk=true)',
        () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeNative: (_, __) =>
            FakePlayerBackend(kind: PlayerBackendKind.native),
      );

      final controller = NiumaPlayerController.dataSource(
        ds,
        options: const NiumaPlayerOptions(forceIjkOnAndroid: true),
        platform: FakePlatformBridge(),
        backendFactory: factory,
      );

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeBackend, PlayerBackendKind.native);
      expect(factory.videoPlayers, isEmpty);
      expect(factory.nativePlayers.length, 1);
      expect(factory.nativeForceIjkArgs, <bool>[true]);

      await controller.dispose();
    });

    test('D. Android default + native succeeds first time → no retry',
        () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeNative: (_, __) =>
            FakePlayerBackend(kind: PlayerBackendKind.native),
      );

      final controller = NiumaPlayerController.dataSource(
        ds,
        platform: FakePlatformBridge(),
        backendFactory: factory,
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeBackend, PlayerBackendKind.native);
      expect(factory.videoPlayers, isEmpty);
      expect(factory.nativePlayers.length, 1);
      expect(factory.nativeForceIjkArgs, <bool>[false]);
      expect(events.whereType<FallbackTriggered>(), isEmpty);
      final selected = events.whereType<BackendSelected>().single;
      expect(selected.kind, PlayerBackendKind.native);

      await sub.cancel();
      await controller.dispose();
    });

    test(
        'E. Android default + native errors → controller retries with forceIjk=true',
        () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeNative: (_, forceIjk) {
          if (!forceIjk) {
            // First (default) attempt: simulate a codec failure mid-prepare.
            return FakePlayerBackend(
              kind: PlayerBackendKind.native,
              initBlock: () async {
                throw StateError('codec unsupported');
              },
            );
          }
          // Retry succeeds.
          return FakePlayerBackend(kind: PlayerBackendKind.native);
        },
      );

      final controller = NiumaPlayerController.dataSource(
        ds,
        platform: FakePlatformBridge(),
        backendFactory: factory,
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      // Both attempts went through, in order.
      expect(factory.nativeForceIjkArgs, <bool>[false, true]);
      expect(factory.nativePlayers.length, 2);
      // The first (failed) backend was disposed.
      expect(factory.nativePlayers[0].disposed, isTrue);
      // The retry backend is the active one.
      expect(controller.activeBackend, PlayerBackendKind.native);

      // Caller-visible events: a FallbackTriggered for the failure, then a
      // BackendSelected for the successful retry.
      final fb = events.whereType<FallbackTriggered>().single;
      expect(fb.reason, FallbackReason.error);
      final selected = events.whereType<BackendSelected>().single;
      expect(selected.kind, PlayerBackendKind.native);

      await sub.cancel();
      await controller.dispose();
    });

    test(
        'F. Android default + native errors twice → initialize() throws',
        () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeNative: (_, __) => FakePlayerBackend(
          kind: PlayerBackendKind.native,
          initBlock: () async {
            throw StateError('hard failure');
          },
        ),
      );

      final controller = NiumaPlayerController.dataSource(
        ds,
        platform: FakePlatformBridge(),
        backendFactory: factory,
      );

      await expectLater(controller.initialize(), throwsStateError);
      // Both attempts ran (default, then forceIjk).
      expect(factory.nativeForceIjkArgs, <bool>[false, true]);

      await controller.dispose();
    });

    test(
        'G. Android default + native init wall-clock timeout → retry kicks in',
        () async {
      // The first native attempt never resolves; the controller should hit
      // its wall-clock timeout and retry with forceIjk=true.
      final firstAttemptCompleter = Completer<void>();
      var nativeCallIndex = 0;

      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeNative: (_, forceIjk) {
          final attempt = nativeCallIndex++;
          if (attempt == 0) {
            return FakePlayerBackend(
              kind: PlayerBackendKind.native,
              initBlock: () => firstAttemptCompleter.future,
            );
          }
          // Retry succeeds.
          return FakePlayerBackend(kind: PlayerBackendKind.native);
        },
      );

      final controller = NiumaPlayerController.dataSource(
        ds,
        options: const NiumaPlayerOptions(
          initTimeout: Duration(milliseconds: 100),
        ),
        platform: FakePlatformBridge(),
        backendFactory: factory,
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeBackend, PlayerBackendKind.native);
      expect(factory.nativeForceIjkArgs, <bool>[false, true]);

      // We expect a timeout fallback emitted from the first native init.
      final fb = events.whereType<FallbackTriggered>();
      expect(fb, isNotEmpty);
      expect(fb.first.reason, FallbackReason.timeout);

      await sub.cancel();
      await controller.dispose();
    });
  });
}
