import 'dart:async';

import 'package:clock/clock.dart';
import 'package:niuma_player/src/orchestration/multi_source.dart';
import 'package:niuma_player/src/player/niuma_player_controller.dart';

/// 池如何创建一个 [NiumaPlayerController]——由 consumer 提供，
/// 池只管生命周期，options / backend / middleware 由工厂决定。
typedef PoolControllerFactory = NiumaPlayerController Function(
  NiumaMediaSource source,
);

/// 池内单条缓存记录：持有 controller + 最近访问时间戳 + 是否就绪。
class _Entry {
  _Entry(this.controller);

  final NiumaPlayerController controller;

  /// 最近一次命中时间，stale 清理按它判过期。
  DateTime lastAccess = clock.now();

  /// 单调递增访问序号——LRU 用它而非 [lastAccess]，避免同毫秒 tie 错挑 victim。
  int accessSeq = 0;

  /// controller 是否已 `initialize()` 完成。
  bool ready = false;

  /// 仍在 init / pause 中的 future；并发同 key 时复用，避免建两个 controller。
  Future<void>? pending;
}

/// 内存感知的 headless 播放器池——feed 多实例场景限容量（LRU evict）
/// + 预加载（init 完即 pause 压 heap）+ stale 清理，防解码 buffer 吃爆堆。
/// 容量按进程堆上限算而非物理 RAM（见 [computeCapacityForHeap]），
/// 按 RAM 定池会 OOM。纯 Dart，可在单测里跑。
class NiumaPlayerPool {
  NiumaPlayerPool({
    required this.controllerFactory,
    this.capacity = 3,
    this.staleDuration = const Duration(seconds: 30),
  }) {
    // 每 staleDuration/2 扫一次：足够及时回收过期 buffer，又不至于太频繁。
    _staleTimer = Timer.periodic(
      Duration(
          milliseconds: (staleDuration.inMilliseconds ~/ 2).clamp(1, 1 << 30)),
      (_) => _sweepStale(),
    );
  }

  /// 池如何创建 controller。见 [PoolControllerFactory]。
  final PoolControllerFactory controllerFactory;

  /// 最大同时存活的 controller 数。超出按 LRU evict。
  final int capacity;

  /// 一个条目多久没被访问（且未被持有）就视作 stale 被清理。
  final Duration staleDuration;

  final Map<String, _Entry> _entries = <String, _Entry>{};

  /// 当前被 acquire 持有 / 正在播的 key——stale 清理永远跳过它们，避免清掉
  /// 正在前台播的 controller。[release] 把 key 移出本集合，它才有资格被清。
  final Set<String> _active = <String>{};

  Timer? _staleTimer;
  bool _disposed = false;
  int _accessClock = 0;

  /// 记一次访问：刷新时间戳（给 stale）+ 递增序号（给 LRU）。
  void _touch(_Entry entry) {
    entry.lastAccess = clock.now();
    entry.accessSeq = ++_accessClock;
  }

  /// 取 source 的主 URL 当池 key——默认线路（[NiumaMediaSource.currentLine]）
  /// 的 [NiumaDataSource.uri]。同一条视频无论多线路，默认线路相同即同 key。
  static String keyFor(NiumaMediaSource source) =>
      source.currentLine.source.uri;

  /// 取得一个就绪的 controller：命中直接返回，未命中建 + `initialize()`；
  /// 超容量先 LRU evict 一个。
  Future<NiumaPlayerController> acquire(NiumaMediaSource source) async {
    final key = keyFor(source);
    _active.add(key);
    final existing = _entries[key];
    if (existing != null) {
      _touch(existing);
      if (existing.ready) return existing.controller;
      // 仍在 init（被 preload 触发）——等它完成，期间别重建。
      try {
        await existing.pending;
      } catch (_) {
        await _remove(key);
        rethrow;
      }
      return existing.controller;
    }
    final entry = await _put(
      key,
      source,
      allowOverflowWhenNoInactiveVictim: true,
    );
    if (entry == null) {
      _active.remove(key);
      throw StateError('Unable to allocate player pool entry for $key');
    }
    final init = entry.controller.initialize();
    entry.pending = init;
    try {
      await init;
      entry.ready = true;
      entry.pending = null;
    } catch (_) {
      await _remove(key);
      rethrow;
    }
    return entry.controller;
  }

  /// 预加载：提前建 + `initialize()` 备用，init 完立刻 `pause()` 阻止
  /// 继续缓冲压低 native heap。已在池则跳过，之后 [acquire] 直接命中。
  Future<void> preload(NiumaMediaSource source) async {
    final key = keyFor(source);
    if (_entries.containsKey(key)) return;
    final entry = await _put(
      key,
      source,
      allowOverflowWhenNoInactiveVictim: false,
    );
    if (entry == null) return;
    final init = entry.controller.initialize().then((_) async {
      await entry.controller.pause();
    });
    entry.pending = init;
    try {
      await init;
      entry.ready = true;
      entry.pending = null;
    } catch (_) {
      await _remove(key);
      rethrow;
    }
  }

  /// 标记 [key] 可回收：移出 active 集合（**不立刻 dispose**），留在池里供
  /// "上滑回去"命中，最终靠容量 LRU + stale 清理回收。
  void release(String key) {
    _active.remove(key);
    final entry = _entries[key];
    if (entry != null) _touch(entry);
  }

  /// 强制移除并立刻 dispose [key] 的 controller（与 [release] 不同），
  /// 解码资源敏感场景离屏后主动调，不等 LRU / stale 回收。
  Future<void> evict(String key) => _remove(key);

  /// 池是否仍持有 [key] 的存活 controller——池可能已因 LRU / stale 回收，
  /// 操作缓存引用前先确认，避免误用已 dispose 的实例。
  bool holds(String key) => _entries.containsKey(key);

  /// 建新条目；超容量先 LRU evict 最旧 inactive。全 active 时 acquire
  /// 允许短暂超容，preload 直接跳过（防 capacity=1 时挤掉当前页）。
  Future<_Entry?> _put(
    String key,
    NiumaMediaSource source, {
    required bool allowOverflowWhenNoInactiveVictim,
  }) async {
    while (_entries.isNotEmpty && _entries.length >= capacity) {
      final victim = _lruInactiveKey();
      if (victim == null) {
        if (allowOverflowWhenNoInactiveVictim) break;
        return null;
      }
      await _remove(victim);
    }
    final entry = _Entry(controllerFactory(source));
    _entries[key] = entry;
    _touch(entry);
    return entry;
  }

  /// 找 accessSeq 最小（最久未访问）的 inactive key。没有可回收项返回 null。
  String? _lruInactiveKey() {
    String? oldest;
    int? oldestSeq;
    for (final e in _entries.entries) {
      if (_active.contains(e.key)) continue;
      if (oldestSeq == null || e.value.accessSeq < oldestSeq) {
        oldest = e.key;
        oldestSeq = e.value.accessSeq;
      }
    }
    return oldest;
  }

  Future<void> _remove(String key) async {
    final entry = _entries.remove(key);
    _active.remove(key);
    await entry?.controller.dispose();
  }

  /// 周期性回收超过 staleDuration 未访问且非 active 的条目。
  void _sweepStale() {
    if (_disposed) return;
    final now = clock.now();
    final stale = <String>[];
    for (final e in _entries.entries) {
      if (_active.contains(e.key)) continue;
      if (now.difference(e.value.lastAccess) > staleDuration) {
        stale.add(e.key);
      }
    }
    for (final key in stale) {
      unawaited(_remove(key));
    }
  }

  /// 按进程堆上限（MB，**不是设备 RAM**）算池容量。阈值参考产品打磨值：
  /// `<192→1`、`<320→2`、`<448→3`、`else→4`。
  static int computeCapacityForHeap(int heapMb) {
    if (heapMb < 192) return 1;
    if (heapMb < 320) return 2;
    if (heapMb < 448) return 3;
    return 4;
  }

  /// 停清理 timer，dispose 池里所有 controller，清空。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _staleTimer?.cancel();
    _staleTimer = null;
    final controllers =
        _entries.values.map((e) => e.controller).toList(growable: false);
    _entries.clear();
    _active.clear();
    await Future.wait(controllers.map((c) => c.dispose()));
  }
}
