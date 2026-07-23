import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';


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

/// Simple controllable fake. Tests provide [initBlock] to drive the
/// "Try-Once-Then-Retry" state machine in [NiumaPlayerController].
class FakePlayerBackend extends PlayerBackend {
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
/// by giving a `makeNative` that picks a different fake per call index.
///
/// The no-arg [FakeBackendFactory()] constructor creates simple, always-
/// succeeding video-player backends and is convenient for tests that only
/// need to inspect [simulatePosition] / [lastSeekTarget].
class FakeBackendFactory implements BackendFactory {
  FakeBackendFactory({
    FakePlayerBackend Function(NiumaDataSource ds)? makeVideoPlayer,
    FakePlayerBackend Function(NiumaDataSource ds)? makeNative,
  })  : makeVideoPlayer = makeVideoPlayer ??
            ((_) => FakePlayerBackend(kind: PlayerBackendKind.videoPlayer)),
        makeNative = makeNative ??
            ((_) => FakePlayerBackend(kind: PlayerBackendKind.native));

  final FakePlayerBackend Function(NiumaDataSource ds) makeVideoPlayer;
  final FakePlayerBackend Function(NiumaDataSource ds) makeNative;

  final List<FakePlayerBackend> videoPlayers = <FakePlayerBackend>[];
  final List<FakePlayerBackend> nativePlayers = <FakePlayerBackend>[];

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
  PlayerBackend createVideoPlayer(NiumaDataSource ds, {bool useAndroidPlatformView = false}) {
    lastSourceFromMiddleware = ds;
    final b = makeVideoPlayer(ds);
    videoPlayers.add(b);
    return b;
  }

  @override
  PlayerBackend createNative(NiumaDataSource ds,
      {bool useAndroidPlatformView = false}) {
    lastSourceFromMiddleware = ds;
    final b = makeNative(ds);
    nativePlayers.add(b);
    return b;
  }
}

/// Stubs the host check so tests don't hit `dart:io` Platform / `kIsWeb`.
class FakePlatformBridge implements PlatformBridge {
  FakePlatformBridge({
    this.isIOS = false,
    this.isWeb = false,
  });

  @override
  final bool isIOS;

  @override
  final bool isWeb;

  @override
  Future<int> processHeapLimitMb() async => 256;

  @override
  Future<void> setKeepScreenOn(bool on) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ds = NiumaDataSource.network('https://example.com/sample.mp4');

  group('NiumaPlayerController state machine', () {
    test('A. iOS always selects VideoPlayerBackend without touching native',
        () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeNative: (_) =>
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
        makeNative: (_) =>
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

    test(
        'C. Android + forceIjkOnAndroid: true goes straight to native(forceIjk=true)',
        () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeNative: (_) =>
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

      await controller.dispose();
    });

    test('D. Android default → video_player 主路径，不触碰 native', () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.videoPlayer),
        makeNative: (_) =>
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

      expect(controller.activeBackend, PlayerBackendKind.videoPlayer);
      expect(factory.videoPlayers.length, 1);
      expect(factory.nativePlayers, isEmpty);
      expect(events.whereType<FallbackTriggered>(), isEmpty);
      final selected = events.whereType<BackendSelected>().single;
      expect(selected.kind, PlayerBackendKind.videoPlayer);

      await sub.cancel();
      await controller.dispose();
    });

    test('E. Android vp 主路径失败 → IJK 兜底（forceIjk=true）', () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) => FakePlayerBackend(
          kind: PlayerBackendKind.videoPlayer,
          initBlock: () async {
            throw StateError('vp source error');
          },
        ),
        makeNative: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.native),
      );

      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds),
        retryPolicy: const RetryPolicy.none(),
        platform: FakePlatformBridge(),
        backendFactory: factory,
      );

      final events = <NiumaPlayerEvent>[];
      final sub = controller.events.listen(events.add);

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      // vp 先试并失败（已 dispose），IJK 兜底成功且 active。
      expect(factory.videoPlayers.length, 1);
      expect(factory.videoPlayers[0].disposed, isTrue);
      expect(controller.activeBackend, PlayerBackendKind.native);

      final fb = events.whereType<FallbackTriggered>().single;
      expect(fb.reason, FallbackReason.error);
      final selected = events.whereType<BackendSelected>().single;
      expect(selected.kind, PlayerBackendKind.native);

      await sub.cancel();
      await controller.dispose();
    });

    test('F. Android vp 与 IJK 兜底双双失败 → initialize() 抛组合异常',
        () async {
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) => FakePlayerBackend(
          kind: PlayerBackendKind.videoPlayer,
          initBlock: () async {
            throw StateError('hard failure');
          },
        ),
        makeNative: (_) => FakePlayerBackend(
          kind: PlayerBackendKind.native,
          initBlock: () async {
            throw StateError('hard failure');
          },
        ),
      );

      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds),
        retryPolicy: const RetryPolicy.none(),
        platform: FakePlatformBridge(),
        backendFactory: factory,
      );

      // 双内核都失败 → 抛组合异常，两段原始错误都可见（修「fallback 错误
      // 掩盖」：只报 IJK 错会把 Exo 的根因如 HTTP 403 吞掉）。
      await expectLater(
        controller.initialize(),
        throwsA(isA<EngineFallbackFailure>()
            .having((e) => e.primary.toString(), 'primary', contains('hard failure'))
            .having((e) => e.fallback.toString(), 'fallback', contains('hard failure'))),
      );
      // vp 一次 + IJK 兜底一次。
      expect(factory.videoPlayers.length, 1);
      // value 也进 error 态且信息带双段
      expect(controller.value.phase, PlayerPhase.error);
      expect(controller.value.error!.message, contains('ExoPlayer'));
      expect(controller.value.error!.message, contains('IJK fallback'));

      await controller.dispose();
    });

    test('F2. initialize() 失败后允许再次调用并重新创建 backend', () async {
      var attempt = 0;
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) {
          final current = attempt++;
          return FakePlayerBackend(
            kind: PlayerBackendKind.videoPlayer,
            initBlock: current == 0
                ? () async => throw StateError('first init failed')
                : null,
          );
        },
      );

      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds),
        retryPolicy: const RetryPolicy.none(),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: factory,
      );

      await expectLater(controller.initialize(), throwsStateError);

      await controller.initialize();
      expect(factory.videoPlayers.length, 2);
      expect(factory.videoPlayers[0].disposed, isTrue,
          reason: 'retry initialize must dispose the failed backend first');
      expect(factory.videoPlayers[1].disposed, isFalse);
      expect(controller.value.phase, PlayerPhase.ready);

      await controller.dispose();
    });

    test('G. Android vp 初始化 wall-clock 超时 → retry 重建 vp backend',
        () async {
      // 第一次 vp 初始化永不完成 → 撞 initTimeout → retry 重建。
      final firstAttemptCompleter = Completer<void>();
      var vpCallIndex = 0;

      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) {
          final attempt = vpCallIndex++;
          if (attempt == 0) {
            return FakePlayerBackend(
              kind: PlayerBackendKind.videoPlayer,
              initBlock: () => firstAttemptCompleter.future,
            );
          }
          return FakePlayerBackend(kind: PlayerBackendKind.videoPlayer);
        },
        makeNative: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.native),
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

      // retry 在 vp 主路径内重建，同路径两次；IJK 兜底无需触发。
      expect(controller.activeBackend, PlayerBackendKind.videoPlayer);
      expect(factory.videoPlayers.length, 2);
      expect(factory.nativePlayers, isEmpty);
      // 第一个（超时的）backend 已 dispose。
      expect(factory.videoPlayers[0].disposed, isTrue);

      await sub.cancel();
      await controller.dispose();
    });

    test('G2. Android vp 超时耗尽 retry → IJK 兜底接管', () async {
      // vp 每次都超时；IJK 兜底成功。
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) => FakePlayerBackend(
          kind: PlayerBackendKind.videoPlayer,
          initBlock: () => Completer<void>().future,
        ),
        makeNative: (_) =>
            FakePlayerBackend(kind: PlayerBackendKind.native),
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
      // vp 重试 3 次全超时（maxAttempts=2 → 3 次尝试），随后 IJK 兜底一次。
      expect(factory.videoPlayers.length, 3);

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
        makeNative: (_) =>
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

    test('RetryPolicy retries network errors and eventually succeeds',
        () async {
      var initCount = 0;
      final fake = FakeBackendFactory(
        makeVideoPlayer: (_) {
          return FakePlayerBackend(
            kind: PlayerBackendKind.videoPlayer,
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
      var vpInits = 0;
      final fake = FakeBackendFactory(
        makeVideoPlayer: (_) {
          return FakePlayerBackend(
            kind: PlayerBackendKind.videoPlayer,
            initBlock: () async {
              vpInits++;
              throw _RetryableError(PlayerErrorCategory.codecUnsupported);
            },
          );
        },
        makeNative: (_) {
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
      // codecUnsupported 短路不重试：vp 只 init 一次（随后 IJK 兜底也失败）。
      expect(vpInits, 1);
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
        'second backend constructed (Android / vp 主路径)', () async {
      var vpIdx = 0;
      final fake = FakeBackendFactory(
        makeVideoPlayer: (_) {
          final attempt = vpIdx++;
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
        platform: FakePlatformBridge(isIOS: false),
        backendFactory: fake,
      );
      await ctrl.initialize();

      // Two distinct backends were constructed (one per attempt).
      expect(fake.videoPlayers.length, 2,
          reason: 'each retry attempt must build a fresh backend');
      expect(fake.videoPlayers[0].disposed, isTrue,
          reason: 'failed backend must be disposed before retry');
      expect(fake.videoPlayers[1].disposed, isFalse);
      expect(fake.nativePlayers, isEmpty);

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

  // TG8 (R2-I3): asset:// URL 在 NiumaMediaSource 构造阶段就被拒——
  // 不再延后到 fetch 时静默吞。
  group('non-http(s) thumbnailVtt 立即拒（TG8 / R2-I3）', () {
    // F5: 形如未闭合 IPv6 的 URL 解析期抛 FormatException → 包成 ArgumentError。
    test('NiumaMediaSource.single 非法 thumbnailVtt 立即抛 ArgumentError（F5）', () {
      expect(
        () => NiumaMediaSource.single(ds, thumbnailVtt: 'http://[bad-ipv6'),
        throwsA(isA<ArgumentError>()),
      );
    });
    test('NiumaMediaSource.lines 非法 thumbnailVtt 立即抛 ArgumentError（F5）', () {
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
    test('asset:// 抛 ArgumentError', () {
      expect(
        () => NiumaMediaSource.single(ds, thumbnailVtt: 'asset:///foo.vtt'),
        throwsA(isA<ArgumentError>()),
      );
    });
    test('file:// 抛 ArgumentError', () {
      expect(
        () => NiumaMediaSource.single(ds, thumbnailVtt: 'file:///x.vtt'),
        throwsA(isA<ArgumentError>()),
      );
    });
    test('data: 抛 ArgumentError', () {
      expect(
        () => NiumaMediaSource.single(ds, thumbnailVtt: 'data:text/plain,'),
        throwsA(isA<ArgumentError>()),
      );
    });
    test('http:///nohost（host 空）抛 ArgumentError', () {
      expect(
        () => NiumaMediaSource.single(ds, thumbnailVtt: 'http:///nohost'),
        throwsA(isA<ArgumentError>()),
      );
    });
    test('纯空格（解析后 scheme/host 都空）抛 ArgumentError', () {
      expect(
        () => NiumaMediaSource.single(ds, thumbnailVtt: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });
    test('合法 https URL 通过', () {
      final src = NiumaMediaSource.single(
        ds,
        thumbnailVtt: 'https://valid.com/x.vtt',
      );
      expect(src.thumbnailVtt, 'https://valid.com/x.vtt');
    });
    test('合法 http URL 通过', () {
      final src = NiumaMediaSource.single(
        ds,
        thumbnailVtt: 'http://valid.com/x.vtt',
      );
      expect(src.thumbnailVtt, 'http://valid.com/x.vtt');
    });
  });

  group('NiumaPlayerValue M12 PiP 字段', () {
    test('默认 isInPictureInPicture = false', () {
      final v = NiumaPlayerValue.uninitialized();
      expect(v.isInPictureInPicture, isFalse);
    });

    test('默认 isPictureInPictureSupported = false', () {
      final v = NiumaPlayerValue.uninitialized();
      expect(v.isPictureInPictureSupported, isFalse);
    });

    test('copyWith(isInPictureInPicture: true) 翻位', () {
      final a = NiumaPlayerValue.uninitialized();
      final b = a.copyWith(isInPictureInPicture: true);
      expect(b.isInPictureInPicture, isTrue);
      expect(a.isInPictureInPicture, isFalse);
    });

    test('copyWith(isPictureInPictureSupported: true) 翻位', () {
      final a = NiumaPlayerValue.uninitialized();
      final b = a.copyWith(isPictureInPictureSupported: true);
      expect(b.isPictureInPictureSupported, isTrue);
      expect(a.isPictureInPictureSupported, isFalse);
    });

    test('equality 包含两个新字段', () {
      final a = NiumaPlayerValue.uninitialized();
      final b = a.copyWith(isInPictureInPicture: true);
      expect(a, isNot(equals(b)));
      final c = a.copyWith(isInPictureInPicture: true);
      expect(b, equals(c));
      expect(b.hashCode, equals(c.hashCode));
    });
  });

  group('R. initialize 失败必须落到 value（phase=error）', () {
    // 复现:IJK prepare 卡死 → Dart initTimeout 抛 TimeoutException,错误只进
    // initialize() 的 future;调用方没 catch 时,靠 value 驱动的 UI 永远停在
    // buffering 无限转圈,无任何失败提示(OPPO 真机实测)。修复后失败必须同步
    // 打进 value.phase=error,错误层自然显示。
    test('initialize 抛错后 value.phase 进 error、error 字段有内容', () async {
      final ds = NiumaDataSource.network('https://example.com/a.mp4');
      final factory = FakeBackendFactory(
        makeVideoPlayer: (_) => FakePlayerBackend(
          kind: PlayerBackendKind.videoPlayer,
          initBlock: () async => throw TimeoutException('prepare 卡死', const Duration(seconds: 30)),
        ),
      );
      final controller = NiumaPlayerController(
        NiumaMediaSource.single(ds),
        retryPolicy: const RetryPolicy.none(),
        platform: FakePlatformBridge(isIOS: true),
        backendFactory: factory,
      );

      await expectLater(controller.initialize(), throwsA(isA<TimeoutException>()));
      expect(controller.value.phase, PlayerPhase.error,
          reason: '失败必须落到 value,UI 错误层才能显示');
      expect(controller.value.error, isNotNull);
      expect(controller.value.error!.category, PlayerErrorCategory.network,
          reason: 'TimeoutException 按现有分类映射到 network');
      await controller.dispose();
    });
  });
}
