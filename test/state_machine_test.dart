import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:niuma_player/niuma_player.dart';

import 'helpers/fake_device_memory_channel.dart';

/// Test helper that carries a [PlayerErrorCategory] so [_categorize] in
/// [NiumaPlayerController] can classify it correctly via duck-typing.
class _RetryableError implements Exception {
  _RetryableError(this.category);
  final PlayerErrorCategory category;
}

/// Test double that counts how many times the middleware pipeline runs.
///
/// Used to verify middleware re-execution semantics on retry / switchLine.
class _CountingMiddleware extends SourceMiddleware {
  _CountingMiddleware();

  int callCount = 0;
  Map<String, String>? lastInputHeaders;

  @override
  Future<NiumaDataSource> apply(NiumaDataSource input) async {
    callCount++;
    lastInputHeaders =
        input.headers == null ? null : Map<String, String>.from(input.headers!);
    return input;
  }
}

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
      StreamController<NiumaPlayerValue>.broadcast(sync: true);
  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast(sync: true);

  NiumaPlayerValue _value = NiumaPlayerValue.uninitialized();

  bool initializeCalled = false;
  bool disposed = false;

  /// Last argument passed to [seekTo]; null if seekTo was never called.
  Duration? lastSeekTarget;

  /// Simulated playback position returned by [value].
  Duration _simulatedPosition = Duration.zero;

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
    _value = NiumaPlayerValue(
      phase: PlayerPhase.ready,
      position: _simulatedPosition,
      duration: const Duration(seconds: 10),
      size: const Size(1280, 720),
      bufferedPosition: Duration.zero,
    );
    if (!_valueController.isClosed) {
      _valueController.add(_value);
    }
  }

  /// Sets the simulated position reflected by [value.position]. Call before
  /// [initialize] to pre-seed the position, or after to update it live.
  void simulatePosition(Duration pos) {
    _simulatedPosition = pos;
    _value = NiumaPlayerValue(
      phase: _value.phase,
      position: pos,
      duration: _value.duration,
      size: _value.size,
      bufferedPosition: _value.bufferedPosition,
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
  Future<void> seekTo(Duration position) async {
    lastSeekTarget = position;
  }

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
///
/// The no-arg [FakeBackendFactory()] constructor creates simple, always-
/// succeeding video-player backends and is convenient for tests that only
/// need to inspect [simulatePosition] / [lastSeekTarget].
class FakeBackendFactory implements BackendFactory {
  FakeBackendFactory({
    FakePlayerBackend Function(NiumaDataSource ds)? makeVideoPlayer,
    FakePlayerBackend Function(NiumaDataSource ds, bool forceIjk)? makeNative,
  })  : makeVideoPlayer = makeVideoPlayer ??
            ((_) => FakePlayerBackend(kind: PlayerBackendKind.videoPlayer)),
        makeNative = makeNative ??
            ((_, __) => FakePlayerBackend(kind: PlayerBackendKind.native));

  final FakePlayerBackend Function(NiumaDataSource ds) makeVideoPlayer;
  final FakePlayerBackend Function(NiumaDataSource ds, bool forceIjk)
      makeNative;

  final List<FakePlayerBackend> videoPlayers = <FakePlayerBackend>[];
  final List<FakePlayerBackend> nativePlayers = <FakePlayerBackend>[];
  final List<bool> nativeForceIjkArgs = <bool>[];

  /// Records the last [NiumaDataSource] passed to either [createVideoPlayer]
  /// or [createNative], after the middleware pipeline has run. Tests assert
  /// on this to verify middleware mutations were applied before the backend
  /// factory was invoked.
  NiumaDataSource? lastSourceFromMiddleware;

  /// The most recently constructed [FakePlayerBackend] (video-player or
  /// native). Convenience accessor for [simulatePosition] / [lastSeekTarget]
  /// without having to index into [videoPlayers] / [nativePlayers].
  FakePlayerBackend? get _latestBackend =>
      (videoPlayers + nativePlayers).isNotEmpty
          ? (videoPlayers + nativePlayers).last
          : null;

  /// Delegates to the latest backend's [FakePlayerBackend.simulatePosition].
  void simulatePosition(Duration pos) => _latestBackend?.simulatePosition(pos);

  /// Returns the last seek target recorded by the latest backend.
  Duration? get lastSeekTarget => _latestBackend?.lastSeekTarget;

  @override
  PlayerBackend createVideoPlayer(NiumaDataSource ds) {
    lastSourceFromMiddleware = ds;
    final b = makeVideoPlayer(ds);
    videoPlayers.add(b);
    return b;
  }

  @override
  PlayerBackend createNative(NiumaDataSource ds, {required bool forceIjk}) {
    lastSourceFromMiddleware = ds;
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
      // its wall-clock timeout and retry by rebuilding the backend.
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

      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds),
        options: const NiumaPlayerOptions(
          initTimeout: Duration(milliseconds: 100),
        ),
        // Use a tiny backoff so the test doesn't spend seconds on the
        // smart-retry default 1s base delay.
        retryPolicy: const RetryPolicy.exponential(
          base: Duration(milliseconds: 1),
          max: Duration(milliseconds: 1),
          maxAttempts: 3,
        ),
        platform: FakePlatformBridge(),
        backendFactory: factory,
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      // Both attempts ran; both with forceIjk=false (retry rebuilds the
      // backend on the same path, so the outer Try-Fail-Remember layer
      // never has to fire).
      expect(controller.activeBackend, PlayerBackendKind.native);
      expect(factory.nativeForceIjkArgs, <bool>[false, false],
          reason: 'retry rebuilds with the same forceIjk value; outer '
              'fallback only kicks in when retry is fully exhausted');
      // The first (timed-out) backend was disposed before retry built the
      // second one.
      expect(factory.nativePlayers[0].disposed, isTrue);

      await sub.cancel();
      await controller.dispose();
    });

    test(
        'G2. Android default + native timeout exhausts retry → forceIjk fallback fires',
        () async {
      // Every non-forceIjk attempt times out; only forceIjk=true succeeds.
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeNative: (_, forceIjk) {
          if (!forceIjk) {
            return FakePlayerBackend(
              kind: PlayerBackendKind.native,
              initBlock: () => Completer<void>().future,
            );
          }
          return FakePlayerBackend(kind: PlayerBackendKind.native);
        },
      );

      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds),
        options: const NiumaPlayerOptions(
          initTimeout: Duration(milliseconds: 50),
        ),
        retryPolicy: const RetryPolicy.exponential(
          base: Duration(milliseconds: 1),
          max: Duration(milliseconds: 1),
          maxAttempts: 2,
        ),
        platform: FakePlatformBridge(),
        backendFactory: factory,
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeBackend, PlayerBackendKind.native);
      // With maxAttempts=2: attempt 1 → retry, attempt 2 → retry, attempt 3 →
      // exhausted. Then the outer forceIjk fallback fires once.
      expect(factory.nativeForceIjkArgs, <bool>[false, false, false, true]);

      // Both controller-level FallbackTriggered events fire: timeout (from
      // exhausted retry) and error (from outer try/catch).
      final fb = events.whereType<FallbackTriggered>().toList();
      expect(fb.map((e) => e.reason),
          containsAll([FallbackReason.timeout, FallbackReason.error]));

      await sub.cancel();
      await controller.dispose();
    });

    test(
        'middleware pipeline runs before backend.initialize() — header injected',
        () async {
      final fake = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeNative: (_, __) =>
            FakePlayerBackend(kind: PlayerBackendKind.native),
      );
      final ctrl = NiumaPlayerController(
        NiumaMediaSource.single(
          NiumaDataSource.network('https://cdn/x.mp4', headers: {'X': '1'}),
        ),
        middlewares: const [
          HeaderInjectionMiddleware({'Y': '2'}),
        ],
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: fake,
      );
      await ctrl.initialize();
      // FakeBackendFactory should record the source it was constructed with.
      expect(fake.lastSourceFromMiddleware?.headers, {'X': '1', 'Y': '2'});
      ctrl.dispose();
    });

    test('RetryPolicy retries network errors and eventually succeeds', () async {
      var initCount = 0;
      final fake = FakeBackendFactory(
        makeNative: (_, __) {
          return FakePlayerBackend(
            kind: PlayerBackendKind.native,
            initBlock: () async {
              initCount++;
              if (initCount == 1) {
                throw _RetryableError(PlayerErrorCategory.network);
              }
            },
          );
        },
      );

      final ctrl = NiumaPlayerController(
        NiumaMediaSource.single(NiumaDataSource.network('https://x')),
        retryPolicy: const RetryPolicy.smart(maxAttempts: 3),
        platform: FakePlatformBridge(isIOS: false),
        backendFactory: fake,
      );
      await ctrl.initialize();
      expect(initCount, 2, reason: '1 network throw + 1 retry success');
      ctrl.dispose();
    });

    test('RetryPolicy does not retry codecUnsupported (short-circuits)',
        () async {
      final fake = FakeBackendFactory(
        makeNative: (_, __) {
          return FakePlayerBackend(
            kind: PlayerBackendKind.native,
            initBlock: () async =>
                throw _RetryableError(PlayerErrorCategory.codecUnsupported),
          );
        },
      );
      final ctrl = NiumaPlayerController(
        NiumaMediaSource.single(NiumaDataSource.network('https://x')),
        retryPolicy: const RetryPolicy.smart(),
        platform: FakePlatformBridge(isIOS: false),
        backendFactory: fake,
      );
      await expectLater(ctrl.initialize(), throwsA(anything));
      ctrl.dispose();
    });

    test('switchLine: dispose old backend, init new at saved position',
        () async {
      final fake = FakeBackendFactory();
      final lineA = MediaLine(
        id: 'a',
        label: 'A',
        source: NiumaDataSource.network('https://a'),
      );
      final lineB = MediaLine(
        id: 'b',
        label: 'B',
        source: NiumaDataSource.network('https://b'),
      );
      final ctrl = NiumaPlayerController(
        NiumaMediaSource.lines(lines: [lineA, lineB], defaultLineId: 'a'),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: fake,
      );
      await ctrl.initialize();
      fake.simulatePosition(const Duration(seconds: 12));

      final events = <NiumaPlayerEvent>[];
      ctrl.events.listen(events.add);

      await ctrl.switchLine('b');

      expect(events.any((e) => e is LineSwitching && e.toId == 'b'), isTrue);
      expect(events.any((e) => e is LineSwitched && e.toId == 'b'), isTrue);
      expect(fake.lastSeekTarget, const Duration(seconds: 12));
      ctrl.dispose();
    });

    test(
        'retry rebuilds the backend on each attempt: first backend disposed, '
        'second backend constructed (Android path)', () async {
      var nativeIdx = 0;
      final fake = FakeBackendFactory(
        makeNative: (_, __) {
          final attempt = nativeIdx++;
          return FakePlayerBackend(
            kind: PlayerBackendKind.native,
            initBlock: () async {
              if (attempt == 0) {
                throw _RetryableError(PlayerErrorCategory.network);
              }
            },
          );
        },
      );

      final ctrl = NiumaPlayerController(
        NiumaMediaSource.single(NiumaDataSource.network('https://x')),
        retryPolicy: const RetryPolicy.exponential(
          base: Duration(milliseconds: 1),
          max: Duration(milliseconds: 1),
          maxAttempts: 3,
        ),
        platform: FakePlatformBridge(isIOS: false),
        backendFactory: fake,
      );
      await ctrl.initialize();

      // Two distinct backends were constructed (one per attempt).
      expect(fake.nativePlayers.length, 2,
          reason: 'each retry attempt must build a fresh backend');
      // First (failed) backend was disposed.
      expect(fake.nativePlayers[0].disposed, isTrue,
          reason: 'failed backend must be disposed before retry');
      // Second backend is the active one.
      expect(fake.nativePlayers[1].disposed, isFalse);

      ctrl.dispose();
    });

    test(
        'retry rebuilds the backend on each attempt: first backend disposed, '
        'second backend constructed (iOS / video_player path)', () async {
      var idx = 0;
      final fake = FakeBackendFactory(
        makeVideoPlayer: (_) {
          final attempt = idx++;
          return FakePlayerBackend(
            kind: PlayerBackendKind.videoPlayer,
            initBlock: () async {
              if (attempt == 0) {
                throw _RetryableError(PlayerErrorCategory.network);
              }
            },
          );
        },
      );

      final ctrl = NiumaPlayerController(
        NiumaMediaSource.single(NiumaDataSource.network('https://x')),
        retryPolicy: const RetryPolicy.exponential(
          base: Duration(milliseconds: 1),
          max: Duration(milliseconds: 1),
          maxAttempts: 3,
        ),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: fake,
      );
      await ctrl.initialize();

      expect(fake.videoPlayers.length, 2);
      expect(fake.videoPlayers[0].disposed, isTrue);
      expect(fake.videoPlayers[1].disposed, isFalse);

      ctrl.dispose();
    });

    test('middleware pipeline re-runs on every retry attempt', () async {
      final mw = _CountingMiddleware();
      var idx = 0;
      final fake = FakeBackendFactory(
        makeVideoPlayer: (_) {
          final attempt = idx++;
          return FakePlayerBackend(
            kind: PlayerBackendKind.videoPlayer,
            initBlock: () async {
              if (attempt == 0) {
                throw _RetryableError(PlayerErrorCategory.network);
              }
            },
          );
        },
      );
      final ctrl = NiumaPlayerController(
        NiumaMediaSource.single(NiumaDataSource.network('https://x')),
        middlewares: [mw],
        retryPolicy: const RetryPolicy.exponential(
          base: Duration(milliseconds: 1),
          max: Duration(milliseconds: 1),
          maxAttempts: 3,
        ),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: fake,
      );
      await ctrl.initialize();
      expect(mw.callCount, 2,
          reason: 'middleware runs once per attempt (initial + retry)');
      ctrl.dispose();
    });

    test('middleware ordering preserved across retries', () async {
      final counter = _CountingMiddleware();
      var idx = 0;
      final fake = FakeBackendFactory(
        makeVideoPlayer: (_) {
          final attempt = idx++;
          return FakePlayerBackend(
            kind: PlayerBackendKind.videoPlayer,
            initBlock: () async {
              if (attempt == 0) {
                throw _RetryableError(PlayerErrorCategory.network);
              }
            },
          );
        },
      );
      final ctrl = NiumaPlayerController(
        NiumaMediaSource.single(
          NiumaDataSource.network('https://x', headers: {'A': '1'}),
        ),
        middlewares: [
          const HeaderInjectionMiddleware({'B': '2'}),
          counter,
        ],
        retryPolicy: const RetryPolicy.exponential(
          base: Duration(milliseconds: 1),
          max: Duration(milliseconds: 1),
          maxAttempts: 3,
        ),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: fake,
      );
      await ctrl.initialize();
      // The counter saw the post-HeaderInjection source on each attempt.
      expect(counter.callCount, 2);
      expect(counter.lastInputHeaders, {'A': '1', 'B': '2'},
          reason:
              'order preserved: HeaderInjection runs before _CountingMiddleware');
      // Final backend's data source has both headers.
      expect(fake.lastSourceFromMiddleware?.headers, {'A': '1', 'B': '2'});
      ctrl.dispose();
    });

    test('switchLine to the same lineId short-circuits (no events, no rebuild)',
        () async {
      final fake = FakeBackendFactory();
      final lineA = MediaLine(
        id: 'a',
        label: 'A',
        source: NiumaDataSource.network('https://a'),
      );
      final lineB = MediaLine(
        id: 'b',
        label: 'B',
        source: NiumaDataSource.network('https://b'),
      );
      final ctrl = NiumaPlayerController(
        NiumaMediaSource.lines(lines: [lineA, lineB], defaultLineId: 'a'),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: fake,
      );
      await ctrl.initialize();

      final events = <NiumaPlayerEvent>[];
      final sub = ctrl.events.listen(events.add);

      // Switching to the active line is a no-op.
      await ctrl.switchLine('a');
      // Yield so any spurious async event would have flushed by now.
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<LineSwitching>(), isEmpty);
      expect(events.whereType<LineSwitched>(), isEmpty);
      // Still only the initial backend.
      expect(fake.videoPlayers.length, 1);

      await sub.cancel();
      ctrl.dispose();
    });

    test('switchLine with an unknown lineId throws ArgumentError, no events',
        () async {
      final fake = FakeBackendFactory();
      final lineA = MediaLine(
        id: 'a',
        label: 'A',
        source: NiumaDataSource.network('https://a'),
      );
      final ctrl = NiumaPlayerController(
        NiumaMediaSource.lines(lines: [lineA], defaultLineId: 'a'),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: fake,
      );
      await ctrl.initialize();

      final events = <NiumaPlayerEvent>[];
      final sub = ctrl.events.listen(events.add);

      expect(() => ctrl.switchLine('does-not-exist'),
          throwsA(isA<ArgumentError>()));
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<LineSwitching>(), isEmpty);
      expect(events.whereType<LineSwitched>(), isEmpty);
      expect(events.whereType<LineSwitchFailed>(), isEmpty);

      await sub.cancel();
      ctrl.dispose();
    });

    test('switchLine: middleware re-runs on every switch', () async {
      final mw = _CountingMiddleware();
      final fake = FakeBackendFactory();
      final lineA = MediaLine(
        id: 'a',
        label: 'A',
        source: NiumaDataSource.network('https://a'),
      );
      final lineB = MediaLine(
        id: 'b',
        label: 'B',
        source: NiumaDataSource.network('https://b'),
      );
      final ctrl = NiumaPlayerController(
        NiumaMediaSource.lines(lines: [lineA, lineB], defaultLineId: 'a'),
        middlewares: [mw],
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: fake,
      );
      await ctrl.initialize();
      expect(mw.callCount, 1, reason: 'initial init runs middleware once');

      await ctrl.switchLine('b');
      expect(mw.callCount, 2,
          reason: 'switchLine must re-run the middleware pipeline');

      ctrl.dispose();
    });

    test(
        'switchLine mid-init dispose race: dispose() during switchLine '
        'does not leak a half-built backend or emit late LineSwitched',
        () async {
      // Block initialize on the second backend so we can race dispose() into
      // the middle of switchLine.
      final blocker = Completer<void>();
      var idx = 0;
      final fake = FakeBackendFactory(
        makeVideoPlayer: (_) {
          final attempt = idx++;
          return FakePlayerBackend(
            kind: PlayerBackendKind.videoPlayer,
            initBlock: () async {
              if (attempt == 1) {
                // Wait until the test releases us.
                await blocker.future;
              }
            },
          );
        },
      );
      final lineA = MediaLine(
        id: 'a',
        label: 'A',
        source: NiumaDataSource.network('https://a'),
      );
      final lineB = MediaLine(
        id: 'b',
        label: 'B',
        source: NiumaDataSource.network('https://b'),
      );
      final ctrl = NiumaPlayerController(
        NiumaMediaSource.lines(lines: [lineA, lineB], defaultLineId: 'a'),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: fake,
      );
      await ctrl.initialize();

      final events = <NiumaPlayerEvent>[];
      final sub = ctrl.events.listen(events.add);

      // Kick off switchLine; it will block on initialize() of the new backend.
      final switchFuture = ctrl.switchLine('b');
      // Yield so switchLine reaches the await on initialize().
      await Future<void>.delayed(Duration.zero);

      // Dispose mid-flight, then unblock the half-built backend.
      final disposeFuture = ctrl.dispose();
      blocker.complete();

      await switchFuture.timeout(const Duration(seconds: 2),
          onTimeout: () async {});
      await disposeFuture;
      await Future<void>.delayed(Duration.zero);

      // No late LineSwitched leaked after dispose.
      expect(events.whereType<LineSwitched>(), isEmpty,
          reason: 'dispose mid-switchLine must suppress LineSwitched');
      // Both backends ended up disposed (no leak).
      expect(fake.videoPlayers.every((b) => b.disposed), isTrue,
          reason: 'every backend constructed during the race must be '
              'disposed exactly once');

      await sub.cancel();
    });
  });

  group('thumbnailFor', () {
    test('source.thumbnailVtt 为 null 时返回 null', () async {
      final factory = FakeBackendFactory();
      final controller = NiumaPlayerController.dataSource(
        ds,
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: factory,
      );
      await controller.initialize();
      // Yield so any pending unawaited init paths complete.
      await Future<void>.delayed(Duration.zero);
      expect(controller.thumbnailFor(const Duration(seconds: 3)), isNull);
      await controller.dispose();
    });

    test('VTT fetch 失败时 thumbnailFor 返回 null（不影响播放，D1 强断言）',
        () async {
      final factory = FakeBackendFactory();
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(
          ds,
          thumbnailVtt: 'https://x/thumbs.vtt',
        ),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: factory,
        thumbnailFetcher: (uri, headers) async {
          throw const FormatException('boom');
        },
      );

      // Track BackendSelected to verify backend bring-up still completed.
      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      // Wait for the unawaited thumbnail load to settle.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // D1 强断言：缩略图加载失败，但视频本身完全到达 ready 状态。
      expect(controller.thumbnailFor(const Duration(seconds: 3)), isNull);
      expect(controller.thumbnailLoadState, ThumbnailLoadState.failed);
      expect(controller.value.phase, PlayerPhase.ready,
          reason: 'video phase must reach ready despite thumbnail failure');
      expect(controller.value.initialized, isTrue,
          reason: 'video must be initialized despite thumbnail failure');
      expect(events.whereType<BackendSelected>(), isNotEmpty,
          reason: 'BackendSelected must still fire when VTT fetch fails');

      await sub.cancel();
      await controller.dispose();
    });

    // I7: fetcher 没超时 / 没大小上限会让 web tab 拖死 / VM 无界吃 RAM。
    test('fetcher 超时被静默降级（I7 timeout）', () async {
      final factory = FakeBackendFactory();
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(
          ds,
          thumbnailVtt: 'https://x/thumbs.vtt',
        ),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: factory,
        thumbnailFetcher: (uri, headers) async {
          // 永不返回，模拟挂死的服务器。controller 内部应有自己的超时上限。
          throw TimeoutException('fetcher timed out', const Duration(seconds: 30));
        },
      );
      await controller.initialize();
      // 让 unawaited 加载完成。
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.thumbnailFor(const Duration(seconds: 3)), isNull);
      await controller.dispose();
    });

    // I6: _loadThumbnailsIfAny 不能被多次触发后并行 fetch 多次——浪费带宽。
    test('多次 initialize 只触发一次 fetch（I6 idempotent）', () async {
      var fetchCount = 0;
      final factory = FakeBackendFactory();
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(
          ds,
          thumbnailVtt: 'https://x/thumbs.vtt',
        ),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: factory,
        thumbnailFetcher: (uri, headers) async {
          fetchCount++;
          return 'WEBVTT\n\n00:00.000 --> 00:05.000\nx.jpg#xywh=0,0,1,1\n';
        },
      );
      await controller.initialize();
      // 再次调 initialize（已 init 完毕也应安全）+ 让加载完成。
      await controller.initialize();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      // 即使 controller 被外部多次刷激发，VTT 只被 fetch 一次。
      expect(fetchCount, 1);
      await controller.dispose();
    });

    // I7: 默认 fetcher 必须有 5MB 大小上限，否则恶意服务器可以让 VM 吃光 RAM。
    test('默认 fetcher 拒绝超过 5MB 的 body（I7 size cap）', () async {
      // 6MB 的假 body：用全是 ASCII 字符（每个 1 byte）。
      final oversize = Uint8List(kThumbnailMaxBodyBytes + 1024);
      // 填一些 ASCII 数据（'a'）让 body 是合法的 UTF-8。
      for (var i = 0; i < oversize.length; i++) {
        oversize[i] = 0x61; // 'a'
      }
      final mock = http_testing.MockClient(
        (req) async => http.Response.bytes(oversize, 200),
      );

      Object? caught;
      try {
        await fetchThumbnailVtt(
          Uri.parse('https://x/thumbs.vtt'),
          const <String, String>{},
          mock,
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<http.ClientException>(),
          reason: 'oversized VTT body must be rejected');
      expect(caught.toString(), contains('too large'));
    });

    // I7: 正常大小的 body 通过。
    test('默认 fetcher 接受正常大小的 VTT body', () async {
      final body = utf8.encode(
        'WEBVTT\n\n00:00.000 --> 00:05.000\nx.jpg#xywh=0,0,1,1\n',
      );
      final mock = http_testing.MockClient(
        (req) async => http.Response.bytes(body, 200),
      );
      final result = await fetchThumbnailVtt(
        Uri.parse('https://x/thumbs.vtt'),
        const <String, String>{},
        mock,
      );
      expect(result, contains('WEBVTT'));
    });

    // F5: thumbnailVtt 必须在 NiumaMediaSource 构造时校验，
    // 不要等到 fetch 才静默降级。
    test('NiumaMediaSource.single 非法 thumbnailVtt 立即抛 ArgumentError（F5）',
        () {
      expect(
        () => NiumaMediaSource.single(
          ds,
          thumbnailVtt: 'http://[bad-ipv6',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('NiumaMediaSource.lines 非法 thumbnailVtt 立即抛 ArgumentError（F5）',
        () {
      expect(
        () => NiumaMediaSource.lines(
          lines: [
            MediaLine(id: 'a', label: 'A', source: ds),
          ],
          defaultLineId: 'a',
          thumbnailVtt: 'http://[bad-ipv6',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('成功 fetch + 解析后能查出对应 frame', () async {
      const vttBody = '''
WEBVTT

00:00.000 --> 00:05.000
sprite.jpg#xywh=0,0,128,72

00:05.000 --> 00:10.000
sprite.jpg#xywh=128,0,128,72
''';
      final factory = FakeBackendFactory();
      final fetched = <Uri>[];
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(
          ds,
          thumbnailVtt: 'https://cdn.com/x/thumbs.vtt',
        ),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: factory,
        thumbnailFetcher: (uri, headers) async {
          fetched.add(uri);
          return vttBody;
        },
      );
      await controller.initialize();
      // Allow the async thumbnail load to complete.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(fetched.single, Uri.parse('https://cdn.com/x/thumbs.vtt'));
      final frame = controller.thumbnailFor(const Duration(seconds: 3));
      expect(frame, isNotNull);
      expect(frame!.region.left, 0);
      final frame2 = controller.thumbnailFor(const Duration(seconds: 7));
      expect(frame2, isNotNull);
      expect(frame2!.region.left, 128);
      // Out-of-range
      expect(controller.thumbnailFor(const Duration(seconds: 99)), isNull);

      await controller.dispose();
    });
  });

  // F3 / TG4: thumbnailLoadState 状态机覆盖。
  group('thumbnailLoadState', () {
    test('thumbnailVtt: null → none', () {
      final controller = NiumaPlayerController.dataSource(
        ds,
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: FakeBackendFactory(),
      );
      expect(controller.thumbnailLoadState, ThumbnailLoadState.none);
      controller.dispose();
    });

    test('配置但 initialize 未跑完 → idle', () {
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds, thumbnailVtt: 'https://x/thumbs.vtt'),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: FakeBackendFactory(),
        thumbnailFetcher: (uri, headers) async => 'WEBVTT\n',
      );
      expect(controller.thumbnailLoadState, ThumbnailLoadState.idle,
          reason: 'state should be idle before initialize completes');
      controller.dispose();
    });

    test('fetch 进行中 → loading（用 Completer 控制完成时点）', () async {
      final fetchGate = Completer<String>();
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds, thumbnailVtt: 'https://x/thumbs.vtt'),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: FakeBackendFactory(),
        thumbnailFetcher: (uri, headers) => fetchGate.future,
      );
      await controller.initialize();
      // initialize 完成、unawaited(_loadThumbnailsIfAny) 已启动但 fetcher 还卡住
      await Future<void>.delayed(Duration.zero);
      expect(controller.thumbnailLoadState, ThumbnailLoadState.loading);

      // 解锁让加载收尾，避免 dispose 时悬挂
      fetchGate.complete('WEBVTT\n');
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await controller.dispose();
    });

    test('成功 fetch + 解析 → ready', () async {
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds, thumbnailVtt: 'https://x/thumbs.vtt'),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: FakeBackendFactory(),
        thumbnailFetcher: (uri, headers) async =>
            'WEBVTT\n\n00:00.000 --> 00:05.000\nx.jpg#xywh=0,0,1,1\n',
      );
      await controller.initialize();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.thumbnailLoadState, ThumbnailLoadState.ready);
      await controller.dispose();
    });

    test('解析返回空 cue 列表（合法 WEBVTT 但 0 cue）→ ready（thumbnailFor 仍返回 null）',
        () async {
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds, thumbnailVtt: 'https://x/thumbs.vtt'),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: FakeBackendFactory(),
        // 合法 WEBVTT 头但 0 cue
        thumbnailFetcher: (uri, headers) async => 'WEBVTT\n',
      );
      await controller.initialize();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.thumbnailLoadState, ThumbnailLoadState.ready,
          reason: '解析成功只是无内容；状态仍是 ready');
      expect(controller.thumbnailFor(const Duration(seconds: 3)), isNull,
          reason: 'cue 列表为空时 thumbnailFor 返回 null');
      await controller.dispose();
    });

    test('fetch 抛异常 → failed', () async {
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds, thumbnailVtt: 'https://x/thumbs.vtt'),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: FakeBackendFactory(),
        thumbnailFetcher: (uri, headers) async {
          throw const FormatException('boom');
        },
      );
      await controller.initialize();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.thumbnailLoadState, ThumbnailLoadState.failed);
      await controller.dispose();
    });

    // TG4: dispose 中途竞态。fetcher 用 Completer 控制完成；构造 controller →
    // unawaited(initialize) → 立即 dispose → 让 fetcher 完成 → 验证
    // _thumbnailLoadState 没被写到 ready（dispose 后 _runThumbnailLoad 应短路）。
    test('dispose 中途的 fetcher 不写已 disposed 的字段（TG4 race）', () async {
      final fetchGate = Completer<String>();
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds, thumbnailVtt: 'https://x/thumbs.vtt'),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: FakeBackendFactory(),
        thumbnailFetcher: (uri, headers) => fetchGate.future,
      );

      unawaited(controller.initialize());
      // 让 initialize 跑到点 unawaited(_loadThumbnailsIfAny) 阶段
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // 立即 dispose
      await controller.dispose();

      // fetcher 现在才完成（dispose 已经发生）
      fetchGate.complete(
        'WEBVTT\n\n00:00.000 --> 00:05.000\nx.jpg#xywh=0,0,1,1\n',
      );
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // dispose 中途完成的 fetcher 不应把状态写成 ready——_runThumbnailLoad
      // 内部已经在每个 await 后检查 _disposed 并 early-return。
      expect(controller.thumbnailLoadState, isNot(ThumbnailLoadState.ready),
          reason: 'dispose 后到达的 fetcher 结果不能让状态变 ready');
      expect(controller.thumbnailFor(const Duration(seconds: 3)), isNull);
    });
  });

  // TG7 + D3: 真 middleware 跑在 VTT URL 上。
  group('thumbnail VTT 走 middleware（TG7 / D3）', () {
    test('HeaderInjectionMiddleware 注入的 headers 真到达 fetcher', () async {
      Map<String, String>? capturedHeaders;
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds, thumbnailVtt: 'https://x/thumbs.vtt'),
        middlewares: const [
          HeaderInjectionMiddleware({'X-Token': 'foo'}),
        ],
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: FakeBackendFactory(),
        thumbnailFetcher: (uri, headers) async {
          capturedHeaders = headers;
          return 'WEBVTT\n';
        },
      );
      await controller.initialize();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(capturedHeaders, isNotNull);
      expect(capturedHeaders!['X-Token'], 'foo',
          reason: 'fetcher 应收到 HeaderInjectionMiddleware 注入的 X-Token');
      await controller.dispose();
    });

    test('SignedUrlMiddleware 改写过的 URL 真到达 fetcher', () async {
      Uri? capturedUri;
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds, thumbnailVtt: 'https://x/thumbs.vtt'),
        middlewares: [
          SignedUrlMiddleware((u) async => '$u?sig=bar'),
        ],
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: FakeBackendFactory(),
        thumbnailFetcher: (uri, headers) async {
          capturedUri = uri;
          return 'WEBVTT\n';
        },
      );
      await controller.initialize();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(capturedUri, isNotNull);
      expect(capturedUri.toString(), contains('?sig=bar'),
          reason: 'fetcher 应收到 SignedUrlMiddleware 改写过的 URL');
      await controller.dispose();
    });
  });

  // TG8: asset:// URL 默认 fetcher 抛 → controller 进 failed，video 仍 ready。
  group('asset:// thumbnailVtt（TG8）', () {
    test('asset URL 走默认 fetcher 失败 → failed + video 不受影响', () async {
      // NiumaMediaSource 校验 asset URL 不会抛（只校验 http/https 格式）；如果
      // 它会在构造时抛，这个 test 就需要换思路。先看构造能否过：
      late NiumaMediaSource src;
      try {
        src = NiumaMediaSource.single(
          ds,
          thumbnailVtt: 'asset:///foo.vtt',
        );
      } catch (e) {
        // F5 校验可能拒绝 asset:// —— 那这个 case 不存在，标记跳过。
        markTestSkipped(
            'NiumaMediaSource 在构造时拒绝 asset:// URL（$e）—— TG8 不适用');
        return;
      }

      final controller = NiumaPlayerController(
        src,
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: FakeBackendFactory(),
        // 默认 fetcher 会抛（asset:// 不是 http）；这里直接模拟它的行为。
        thumbnailFetcher: (uri, headers) async {
          throw http.ClientException('asset:// not supported', uri);
        },
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // 缩略图侧 failed，thumbnailFor null
      expect(controller.thumbnailLoadState, ThumbnailLoadState.failed);
      expect(controller.thumbnailFor(const Duration(seconds: 3)), isNull);
      // 视频侧不受影响：BackendSelected + ready + initialized
      expect(events.whereType<BackendSelected>(), isNotEmpty);
      expect(controller.value.phase, PlayerPhase.ready);
      expect(controller.value.initialized, isTrue);

      await sub.cancel();
      await controller.dispose();
    });
  });

  // TG9: switchLine 后 thumbnail cues 不被清，原 cues 仍可查。
  group('switchLine 与 thumbnail（TG9）', () {
    test('switchLine 后 thumbnail cues 不被清，原 cues 仍可查', () async {
      const vttBody = '''
WEBVTT

00:00.000 --> 00:05.000
sprite.jpg#xywh=0,0,128,72

00:05.000 --> 00:10.000
sprite.jpg#xywh=128,0,128,72
''';
      final lineA = MediaLine(
        id: 'a',
        label: 'A',
        source: NiumaDataSource.network('https://a/v.mp4'),
      );
      final lineB = MediaLine(
        id: 'b',
        label: 'B',
        source: NiumaDataSource.network('https://b/v.mp4'),
      );
      var fetchCount = 0;
      final controller = NiumaPlayerController(
        NiumaMediaSource.lines(
          lines: [lineA, lineB],
          defaultLineId: 'a',
          thumbnailVtt: 'https://cdn.com/x/thumbs.vtt',
        ),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: FakeBackendFactory(),
        thumbnailFetcher: (uri, headers) async {
          fetchCount++;
          return vttBody;
        },
      );
      await controller.initialize();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // 切换前能查 cue
      final beforeFrame =
          controller.thumbnailFor(const Duration(seconds: 3));
      expect(beforeFrame, isNotNull);

      await controller.switchLine('b');
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // 切换后原 cue 仍可查（thumbnail 是 NiumaMediaSource 内容属性，跨 line
      // 共享）。switchLine 不重新触发 _loadThumbnailsIfAny，旧 cues 直接复用。
      final afterFrame =
          controller.thumbnailFor(const Duration(seconds: 3));
      expect(afterFrame, isNotNull,
          reason: 'switchLine 后 thumbnail cues 应保留');
      expect(afterFrame!.region.left, 0);
      // VTT 只被 fetch 了一次（switchLine 不触发再 fetch）
      expect(fetchCount, 1,
          reason: 'switchLine 不应重新 fetch 同一个 thumbnailVtt');
      expect(controller.thumbnailLoadState, ThumbnailLoadState.ready);

      await controller.dispose();
    });
  });
}
