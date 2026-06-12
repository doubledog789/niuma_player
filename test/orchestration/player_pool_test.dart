import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

/// 轻量 fake backend——只需驱动 [NiumaPlayerController.initialize] 走通，
/// 并记录 play / pause / dispose 调用供池行为断言。
class _FakeBackend extends PlayerBackend {
  _FakeBackend({this.initBlock});

  final Future<void> Function()? initBlock;

  @override
  PlayerBackendKind get kind => PlayerBackendKind.videoPlayer;

  final StreamController<NiumaPlayerValue> _values =
      StreamController<NiumaPlayerValue>.broadcast(sync: true);
  final StreamController<NiumaPlayerEvent> _events =
      StreamController<NiumaPlayerEvent>.broadcast(sync: true);

  bool playCalled = false;
  bool pauseCalled = false;
  bool disposed = false;

  @override
  int? get textureId => null;

  @override
  NiumaPlayerValue get value => NiumaPlayerValue.uninitialized();

  @override
  Stream<NiumaPlayerValue> get valueStream => _values.stream;

  @override
  Stream<NiumaPlayerEvent> get eventStream => _events.stream;

  @override
  Future<void> initialize() async {
    if (initBlock != null) {
      await initBlock!();
    }
    _values.add(NiumaPlayerValue(
      phase: PlayerPhase.ready,
      position: Duration.zero,
      duration: const Duration(seconds: 10),
      size: const Size(1280, 720),
      bufferedPosition: Duration.zero,
    ));
  }

  @override
  Future<void> play() async => playCalled = true;
  @override
  Future<void> pause() async => pauseCalled = true;
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setLooping(bool looping) async {}
  @override
  Future<double> getBrightness() async => 0.0;
  @override
  Future<bool> setBrightness(double value) async => false;
  @override
  Future<double> getSystemVolume() async => 0.0;
  @override
  Future<bool> setSystemVolume(double value) async => false;
  @override
  Future<bool> enterPictureInPicture({
    required int aspectNum,
    required int aspectDen,
    bool unsafeAutoBackground = false,
  }) async =>
      false;
  @override
  Future<bool> exitPictureInPicture() async => false;
  @override
  Future<bool> queryPictureInPictureSupport() async => false;
  @override
  Future<void> updatePictureInPictureActions({
    required bool isPlaying,
  }) async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await _values.close();
    await _events.close();
  }
}

class _FakeFactory implements BackendFactory {
  _FakeFactory({this.makeBackend});

  final _FakeBackend Function()? makeBackend;

  final List<_FakeBackend> created = <_FakeBackend>[];

  @override
  PlayerBackend createVideoPlayer(NiumaDataSource ds) {
    final b = makeBackend?.call() ?? _FakeBackend();
    created.add(b);
    return b;
  }

  @override
  PlayerBackend createNative(NiumaDataSource ds, {required bool forceIjk, bool useAndroidPlatformView = false}) {
    final b = makeBackend?.call() ?? _FakeBackend();
    created.add(b);
    return b;
  }
}

class _FakeBridge implements PlatformBridge {
  @override
  bool get isIOS => true; // 走 video_player 路径，避免触碰 native 设备记忆
  @override
  bool get isWeb => false;
  @override
  Future<String> deviceFingerprint() async => 'test';
  @override
  Future<int> processHeapLimitMb() async => 256;
  @override
  Future<void> setKeepScreenOn(bool on) async {}
}

NiumaMediaSource _src(String url) =>
    NiumaMediaSource.single(NiumaDataSource.network(url));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 计数：每次池建 controller 调了多少次工厂，用于"命中不重复建"断言。
  int factoryCalls = 0;

  PoolControllerFactory factoryWith(_FakeFactory backendFactory) {
    return (source) {
      factoryCalls++;
      return NiumaPlayerController(
        source,
        platform: _FakeBridge(),
        backendFactory: backendFactory,
      );
    };
  }

  setUp(() => factoryCalls = 0);

  group('computeCapacityForHeap', () {
    test('阈值映射', () {
      expect(NiumaPlayerPool.computeCapacityForHeap(128), 1);
      expect(NiumaPlayerPool.computeCapacityForHeap(191), 1);
      expect(NiumaPlayerPool.computeCapacityForHeap(192), 2);
      expect(NiumaPlayerPool.computeCapacityForHeap(319), 2);
      expect(NiumaPlayerPool.computeCapacityForHeap(320), 3);
      expect(NiumaPlayerPool.computeCapacityForHeap(447), 3);
      expect(NiumaPlayerPool.computeCapacityForHeap(448), 4);
      expect(NiumaPlayerPool.computeCapacityForHeap(1024), 4);
    });
  });

  group('acquire', () {
    test('同 key 命中复用，不重复建 controller', () async {
      final bf = _FakeFactory();
      final pool = NiumaPlayerPool(controllerFactory: factoryWith(bf));

      final c1 = await pool.acquire(_src('https://x/a.mp4'));
      final c2 = await pool.acquire(_src('https://x/a.mp4'));

      expect(identical(c1, c2), isTrue);
      expect(factoryCalls, 1);

      await pool.dispose();
    });

    test('不同 key 建新 controller', () async {
      final bf = _FakeFactory();
      final pool = NiumaPlayerPool(controllerFactory: factoryWith(bf));

      final c1 = await pool.acquire(_src('https://x/a.mp4'));
      final c2 = await pool.acquire(_src('https://x/b.mp4'));

      expect(identical(c1, c2), isFalse);
      expect(factoryCalls, 2);

      await pool.dispose();
    });

    test('超容量时按 LRU evict 最旧条目并 dispose', () async {
      final bf = _FakeFactory();
      final pool = NiumaPlayerPool(
        controllerFactory: factoryWith(bf),
        capacity: 2,
      );

      final a = await pool.acquire(_src('https://x/a.mp4'));
      await pool.acquire(_src('https://x/b.mp4'));
      // touch a 让 b 成为最旧的
      await pool.acquire(_src('https://x/a.mp4'));
      // release b 让它成为可回收的 inactive 条目；active 条目不能被容量回收。
      pool.release('https://x/b.mp4');
      // 第三个 key 超容量 → 应 evict b（最旧），a 保活
      await pool.acquire(_src('https://x/c.mp4'));
      // evict 的 dispose 是 unawaited，让其 dispose 链（含 stream 订阅
      // cancel）跑完再断言。
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // a 的 backend 没被 dispose
      expect(bf.created[0].disposed, isFalse);
      // b 的 backend 被 dispose
      expect(bf.created[1].disposed, isTrue);
      // a 仍是池里同一实例（命中，不重建）
      final aAgain = await pool.acquire(_src('https://x/a.mp4'));
      expect(identical(a, aAgain), isTrue);

      await pool.dispose();
    });

    test('容量满且全是 active 时 acquire 新 key 不 dispose 当前 active', () async {
      final bf = _FakeFactory();
      final pool = NiumaPlayerPool(
        controllerFactory: factoryWith(bf),
        capacity: 1,
      );

      await pool.acquire(_src('https://x/a.mp4'));
      await pool.acquire(_src('https://x/b.mp4'));

      expect(bf.created.length, 2);
      expect(bf.created[0].disposed, isFalse,
          reason: 'active controller must not be evicted by a new acquire');
      expect(bf.created[1].disposed, isFalse);

      await pool.dispose();
    });

    test('initialize 失败会清理坏 entry，后续 acquire 可重新创建', () async {
      var attempt = 0;
      final bf = _FakeFactory(
        makeBackend: () {
          final current = attempt++;
          return _FakeBackend(
            initBlock: current == 0
                ? () async => throw StateError('init failed')
                : null,
          );
        },
      );
      final pool = NiumaPlayerPool(controllerFactory: factoryWith(bf));
      final source = _src('https://x/a.mp4');

      await expectLater(pool.acquire(source), throwsStateError);
      expect(pool.holds('https://x/a.mp4'), isFalse);
      expect(bf.created.single.disposed, isTrue);

      final c = await pool.acquire(source);
      expect(c, isA<NiumaPlayerController>());
      expect(factoryCalls, 2);
      expect(bf.created.length, 2);

      await pool.dispose();
    });
  });

  group('preload', () {
    test('preload 后 init 完立刻 pause，acquire 命中不重建', () async {
      final bf = _FakeFactory();
      final pool = NiumaPlayerPool(controllerFactory: factoryWith(bf));

      await pool.preload(_src('https://x/a.mp4'));
      expect(factoryCalls, 1);
      // preload 对刚建好的 backend 调了 pause
      expect(bf.created.single.pauseCalled, isTrue);

      await pool.acquire(_src('https://x/a.mp4'));
      // 命中预加载，没有重建
      expect(factoryCalls, 1);

      await pool.dispose();
    });

    test('已在池则跳过', () async {
      final bf = _FakeFactory();
      final pool = NiumaPlayerPool(controllerFactory: factoryWith(bf));

      await pool.acquire(_src('https://x/a.mp4'));
      await pool.preload(_src('https://x/a.mp4'));
      expect(factoryCalls, 1);

      await pool.dispose();
    });

    test('capacity=1 且当前页 active 时 preload 跳过，不 dispose 当前页', () async {
      final bf = _FakeFactory();
      final pool = NiumaPlayerPool(
        controllerFactory: factoryWith(bf),
        capacity: 1,
      );

      await pool.acquire(_src('https://x/a.mp4'));
      await pool.preload(_src('https://x/b.mp4'));

      expect(factoryCalls, 1);
      expect(bf.created.single.disposed, isFalse);
      expect(pool.holds('https://x/a.mp4'), isTrue);
      expect(pool.holds('https://x/b.mp4'), isFalse);

      await pool.dispose();
    });

    test('preload initialize 失败会清理坏 entry，后续 preload 可重试', () async {
      var attempt = 0;
      final bf = _FakeFactory(
        makeBackend: () {
          final current = attempt++;
          return _FakeBackend(
            initBlock: current == 0
                ? () async => throw StateError('preload failed')
                : null,
          );
        },
      );
      final pool = NiumaPlayerPool(controllerFactory: factoryWith(bf));
      final source = _src('https://x/a.mp4');

      await expectLater(pool.preload(source), throwsStateError);
      expect(pool.holds('https://x/a.mp4'), isFalse);
      expect(bf.created.single.disposed, isTrue);

      await pool.preload(source);
      expect(pool.holds('https://x/a.mp4'), isTrue);
      expect(factoryCalls, 2);
      expect(bf.created.length, 2);

      await pool.dispose();
    });
  });

  group('evict', () {
    test('立刻 dispose 指定条目并从池移除', () async {
      final bf = _FakeFactory();
      final pool = NiumaPlayerPool(controllerFactory: factoryWith(bf));

      await pool.acquire(_src('https://x/a.mp4'));
      await pool.evict('https://x/a.mp4');

      expect(pool.holds('https://x/a.mp4'), isFalse);
      expect(bf.created.single.disposed, isTrue);

      await pool.dispose();
    });

    test('active 条目也可被显式 evict', () async {
      final bf = _FakeFactory();
      final pool = NiumaPlayerPool(controllerFactory: factoryWith(bf));

      await pool.acquire(_src('https://x/a.mp4'));
      await pool.evict('https://x/a.mp4');
      await pool.acquire(_src('https://x/a.mp4'));

      expect(factoryCalls, 2);
      expect(bf.created.first.disposed, isTrue);
      expect(bf.created.last.disposed, isFalse);

      await pool.dispose();
    });
  });

  group('stale 清理', () {
    // 用真实事件循环 + 极短 staleDuration：fakeAsync 不能完整 drain
    // controller.dispose 里 broadcast stream 订阅 cancel 的调度，所以这里
    // 走真定时器，等过期周期跑过后断言。
    test('过期且已 release 的条目被 dispose 并移除', () async {
      final bf = _FakeFactory();
      final pool = NiumaPlayerPool(
        controllerFactory: factoryWith(bf),
        staleDuration: const Duration(milliseconds: 40),
      );

      await pool.acquire(_src('https://x/a.mp4'));
      pool.release('https://x/a.mp4'); // 标记可回收

      // 等过 staleDuration + 一个清理周期（period = staleDuration/2 = 20ms）。
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(bf.created.single.disposed, isTrue);

      await pool.dispose();
    });

    test('active（持有中、未 release）条目跨过期周期也不被清', () async {
      final bf = _FakeFactory();
      final pool = NiumaPlayerPool(
        controllerFactory: factoryWith(bf),
        staleDuration: const Duration(milliseconds: 40),
      );

      await pool.acquire(_src('https://x/a.mp4'));
      // 不 release → 仍 active，等清理周期跑过也不该被 dispose
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(bf.created.single.disposed, isFalse);

      await pool.dispose();
    });
  });

  test('dispose 停 timer 并清空所有 controller', () async {
    final bf = _FakeFactory();
    final pool = NiumaPlayerPool(controllerFactory: factoryWith(bf));

    await pool.acquire(_src('https://x/a.mp4'));
    await pool.acquire(_src('https://x/b.mp4'));
    await pool.dispose();

    expect(bf.created[0].disposed, isTrue);
    expect(bf.created[1].disposed, isTrue);
  });
}
