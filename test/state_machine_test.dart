import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple controllable fake. Tests call [completeInit] / [failInit] / leave
/// pending to drive the Try-Fail-Remember state machine.
class FakePlayerBackend implements PlayerBackend {
  FakePlayerBackend({
    required this.kind,
    this.initFuture,
  });

  @override
  final PlayerBackendKind kind;

  /// If non-null, [initialize] awaits this. Otherwise it completes immediately.
  final Future<void>? initFuture;

  final StreamController<NiumaPlayerValue> _valueController =
      StreamController<NiumaPlayerValue>.broadcast();
  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast();

  NiumaPlayerValue _value = NiumaPlayerValue.uninitialized();

  bool initializeCalled = false;
  bool disposed = false;

  @override
  int? get textureId => kind == PlayerBackendKind.ijk ? 42 : null;

  @override
  NiumaPlayerValue get value => _value;

  @override
  Stream<NiumaPlayerValue> get valueStream => _valueController.stream;

  @override
  Stream<NiumaPlayerEvent> get eventStream => _eventController.stream;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
    if (initFuture != null) {
      await initFuture;
    }
    _value = const NiumaPlayerValue(
      initialized: true,
      position: Duration.zero,
      duration: Duration(seconds: 10),
      size: Size(1280, 720),
      isPlaying: false,
      isBuffering: false,
    );
    if (!_valueController.isClosed) {
      _valueController.add(_value);
    }
  }

  /// Simulate backend-level error event.
  void emitError(String message) {
    _eventController.add(
      FallbackTriggered(FallbackReason.error, errorCode: message),
    );
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
  Future<void> dispose() async {
    disposed = true;
    await _valueController.close();
    await _eventController.close();
  }
}

/// Factory the controller calls to create the actual backends. We swap this
/// in tests to dispense [FakePlayerBackend] rather than the real ones.
class FakeBackendFactory implements BackendFactory {
  FakeBackendFactory({
    required this.makeVideoPlayer,
    required this.makeIjk,
  });

  final FakePlayerBackend Function(NiumaDataSource ds) makeVideoPlayer;
  final FakePlayerBackend Function(NiumaDataSource ds) makeIjk;

  final List<FakePlayerBackend> videoPlayers = <FakePlayerBackend>[];
  final List<FakePlayerBackend> ijkPlayers = <FakePlayerBackend>[];

  @override
  PlayerBackend createVideoPlayer(NiumaDataSource ds) {
    final b = makeVideoPlayer(ds);
    videoPlayers.add(b);
    return b;
  }

  @override
  PlayerBackend createIjk(NiumaDataSource ds) {
    final b = makeIjk(ds);
    ijkPlayers.add(b);
    return b;
  }
}

/// Stubs the host check (iOS vs Android) + fingerprint lookup so tests don't
/// hit the MethodChannel.
class FakePlatformBridge implements PlatformBridge {
  FakePlatformBridge({
    required this.isIOS,
    this.fingerprint = 'fake-fp',
  });

  @override
  final bool isIOS;

  final String fingerprint;

  @override
  Future<String> deviceFingerprint() async => fingerprint;
}

void main() {
  final ds = NiumaDataSource.network('https://example.com/sample.mp4');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('NiumaPlayerController state machine', () {
    test('A. iOS always selects VideoPlayerBackend without touching IJK',
        () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeIjk: (_) => FakePlayerBackend(kind: PlayerBackendKind.ijk),
      );

      final controller = NiumaPlayerController(
        ds,
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: factory,
        deviceMemory: DeviceMemory(),
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeBackend, PlayerBackendKind.videoPlayer);
      expect(factory.videoPlayers.length, 1);
      expect(factory.ijkPlayers, isEmpty);
      expect(
        events.whereType<BackendSelected>().single,
        isA<BackendSelected>()
            .having((e) => e.kind, 'kind', PlayerBackendKind.videoPlayer)
            .having((e) => e.fromMemory, 'fromMemory', false),
      );

      await sub.cancel();
      await controller.dispose();
    });

    test('B. Android + forceIjkOnAndroid: true goes straight to IJK',
        () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeIjk: (_) => FakePlayerBackend(kind: PlayerBackendKind.ijk),
      );

      final controller = NiumaPlayerController(
        ds,
        options: const NiumaPlayerOptions(forceIjkOnAndroid: true),
        platform: FakePlatformBridge(isIOS: false),
        backendFactory: factory,
        deviceMemory: DeviceMemory(),
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeBackend, PlayerBackendKind.ijk);
      expect(factory.videoPlayers, isEmpty);
      expect(factory.ijkPlayers.length, 1);

      await sub.cancel();
      await controller.dispose();
    });

    test(
        'C. Android + memory hit -> IJK directly; event includes fromMemory:true',
        () async {
      final memory = DeviceMemory();
      await memory.markIjkNeeded('fake-fp');

      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeIjk: (_) => FakePlayerBackend(kind: PlayerBackendKind.ijk),
      );

      final controller = NiumaPlayerController(
        ds,
        platform: FakePlatformBridge(isIOS: false, fingerprint: 'fake-fp'),
        backendFactory: factory,
        deviceMemory: memory,
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeBackend, PlayerBackendKind.ijk);
      expect(factory.videoPlayers, isEmpty);
      expect(factory.ijkPlayers.length, 1);

      final selected = events.whereType<BackendSelected>().single;
      expect(selected.kind, PlayerBackendKind.ijk);
      expect(selected.fromMemory, isTrue);

      await sub.cancel();
      await controller.dispose();
    });

    test(
        'D. Android + memory miss + VP succeeds -> VP; no fallback event',
        () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeIjk: (_) => FakePlayerBackend(kind: PlayerBackendKind.ijk),
      );

      final controller = NiumaPlayerController(
        ds,
        platform: FakePlatformBridge(isIOS: false),
        backendFactory: factory,
        deviceMemory: DeviceMemory(),
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeBackend, PlayerBackendKind.videoPlayer);
      expect(factory.videoPlayers.length, 1);
      expect(factory.ijkPlayers, isEmpty);
      expect(events.whereType<FallbackTriggered>(), isEmpty);
      expect(
        events.whereType<BackendSelected>().single.fromMemory,
        isFalse,
      );

      await sub.cancel();
      await controller.dispose();
    });

    test(
        'E. Android + memory miss + VP errors -> falls back to IJK; emits FallbackTriggered(error)',
        () async {
      // A completer we never complete: the fake emits a FallbackTriggered event
      // on its eventStream, which the controller's local listener picks up and
      // uses to drive fallback. We intentionally do NOT also error the init
      // future — that would leak an unhandled async error because the
      // controller tears down the backend (and its init future listener) as
      // soon as the event-driven fallback kicks in.
      final vpInitCompleter = Completer<void>();

      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) {
          final b = FakePlayerBackend(
            kind: PlayerBackendKind.videoPlayer,
            initFuture: vpInitCompleter.future,
          );
          // Emit AFTER the controller has finished setting up its event stream
          // subscription. Broadcast streams don't replay events to late
          // subscribers, so a scheduleMicrotask here races with _attachBackend
          // and can lose the error.
          Future<void>.delayed(
            Duration.zero,
            () => b.emitError('codec not supported'),
          );
          return b;
        },
        makeIjk: (_) => FakePlayerBackend(kind: PlayerBackendKind.ijk),
      );

      final memory = DeviceMemory();
      final controller = NiumaPlayerController(
        ds,
        platform: FakePlatformBridge(isIOS: false, fingerprint: 'dev-e'),
        backendFactory: factory,
        deviceMemory: memory,
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeBackend, PlayerBackendKind.ijk);
      expect(factory.videoPlayers.length, 1);
      expect(factory.ijkPlayers.length, 1);
      expect(factory.videoPlayers.first.disposed, isTrue);

      final fb = events.whereType<FallbackTriggered>();
      expect(fb, isNotEmpty);
      expect(fb.first.reason, FallbackReason.error);

      // The failure should have been persisted for next time.
      expect(await memory.shouldUseIjk('dev-e'), isTrue);

      await sub.cancel();
      await controller.dispose();
    });

    test(
        'F. Android + VP init timeout -> falls back to IJK; emits FallbackTriggered(timeout)',
        () async {
      // fakeAsync doesn't play well with SharedPreferences's MethodChannel
      // round-trip, so use a very short real timeout instead.
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final vpNever = Completer<void>();

      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) => FakePlayerBackend(
          kind: PlayerBackendKind.videoPlayer,
          initFuture: vpNever.future,
        ),
        makeIjk: (_) => FakePlayerBackend(kind: PlayerBackendKind.ijk),
      );

      final controller = NiumaPlayerController(
        ds,
        options: const NiumaPlayerOptions(
          initTimeout: Duration(milliseconds: 100),
        ),
        platform: FakePlatformBridge(isIOS: false, fingerprint: 'dev-f'),
        backendFactory: factory,
        deviceMemory: DeviceMemory(),
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      // Give any trailing async work a turn.
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeBackend, PlayerBackendKind.ijk);
      expect(factory.videoPlayers.length, 1);
      expect(factory.ijkPlayers.length, 1);

      final fb = events.whereType<FallbackTriggered>();
      expect(fb, isNotEmpty);
      expect(fb.first.reason, FallbackReason.timeout);

      await sub.cancel();
      await controller.dispose();
    });
  });
}
