import 'package:flutter/foundation.dart';

import '../orchestration/danmaku_bucket_loader.dart';
import '../orchestration/danmaku_models.dart';

/// 弹幕的核心持有者：items 列表 + DanmakuSettings + lazy loader 桥接。
///
/// 业务侧通常构造 1 个 controller 与 NiumaPlayer 共用全生命周期，
/// dataSource 切换时调 [resetForNewSource] 或重建。
class NiumaDanmakuController extends ChangeNotifier {
  /// 构造一个 controller。
  ///
  /// [loader] 可选，提供后会在 [ensureLoadedFor] 时按 [DanmakuSettings.bucketSize]
  /// 切片懒加载。[initial] 为初始 settings，省略则使用默认值。
  NiumaDanmakuController({
    DanmakuLoader? loader,
    DanmakuSettings? initial,
  })  : _settings = initial ?? const DanmakuSettings(),
        _bucketLoader = DanmakuBucketLoader(
          loader: loader,
          bucketSize: (initial ?? const DanmakuSettings()).bucketSize,
        );

  DanmakuSettings _settings;
  final DanmakuBucketLoader _bucketLoader;
  final List<DanmakuItem> _items = <DanmakuItem>[];

  /// 当前 settings（不可变）。
  DanmakuSettings get settings => _settings;

  /// 已知 items，按 position 升序。请勿直接修改。
  List<DanmakuItem> get items => List<DanmakuItem>.unmodifiable(_items);

  /// 单条加入。O(log N) 二分插入。触发 notify。
  void add(DanmakuItem item) {
    _insertSorted(item);
    notifyListeners();
  }

  /// 批量加入。一次性 notify。
  void addAll(Iterable<DanmakuItem> items) {
    if (items.isEmpty) return;
    for (final it in items) {
      _insertSorted(it);
    }
    notifyListeners();
  }

  void _insertSorted(DanmakuItem it) {
    final ms = it.position.inMilliseconds;
    var lo = 0;
    var hi = _items.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_items[mid].position.inMilliseconds <= ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _items.insert(lo, it);
  }

  /// 清空 items（不动 settings）。
  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  /// 更新 settings。不同时触发 notify。
  void updateSettings(DanmakuSettings next) {
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
  }

  /// 取 `[0, position + window]` 时间范围内的 items。
  ///
  /// 返回 `item.position <= position + window` 的所有 items，
  /// 即已入场及即将在 window 时长内入场的弹幕集合（用于渲染预热）。
  /// 调用方可自行以 `item.position <= position` 过滤已入场 items。
  ///
  /// 二分找下界（从 index 0 起），线性扫到上界为止。
  /// 复杂度 O(log N + visible)。
  Iterable<DanmakuItem> visibleAt(Duration position,
      {required Duration window}) sync* {
    final upperMs = position.inMilliseconds + window.inMilliseconds;
    // 所有 items 均从 index 0 开始，二分找上界截断点。
    var lo = 0;
    var hi = _items.length;
    // 找第一个 > upperMs 的 index（上界 exclusive）。
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_items[mid].position.inMilliseconds <= upperMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = 0; i < lo; i++) {
      yield _items[i];
    }
  }

  /// 触发 [position] 所在桶懒加载。已加载或 loader 为 null 时是 no-op。
  Future<void> ensureLoadedFor(Duration position) async {
    final fresh = await _bucketLoader.ensureLoaded(position);
    if (fresh.isEmpty) return;
    addAll(fresh);
  }

  /// 切换视频源时调用。清空 items + bucket cache + 触发 notify。
  void resetForNewSource() {
    _bucketLoader.clear();
    clear();
  }
}
