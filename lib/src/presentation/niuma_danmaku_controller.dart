import 'dart:collection';

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

  late final UnmodifiableListView<DanmakuItem> _itemsView =
      UnmodifiableListView(_items);

  /// 已知 items，按 position 升序的只读视图。
  ///
  /// 返回的是 [_items] 的 [UnmodifiableListView] 包装（非快照），所以底层
  /// list 变化会被自动反映；调用方对返回值的写操作会抛 [UnsupportedError]。
  /// painter 每帧调用本 getter 零拷贝开销。
  List<DanmakuItem> get items => _itemsView;

  /// 单条加入。二分定位 O(log N) + List.insert O(N) 内存移动 = 整体 O(N)。
  /// 触发 notify。
  void add(DanmakuItem item) {
    _insertSorted(item);
    notifyListeners();
  }

  /// 批量加入。一次性 notify。
  void addAll(Iterable<DanmakuItem> items) {
    final list = items is List<DanmakuItem> ? items : items.toList();
    if (list.isEmpty) return;
    for (final it in list) {
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

  /// 取窗口 `[position - window, position]` 内的 items。
  ///
  /// 用于 painter 取"已经入场、还没离场"的弹幕：scroll 弹幕在
  /// `[item.position, item.position + scrollDuration]` 期间可见，所以
  /// painter 当前时刻 currentPos 在该区间等价于
  /// `item.position ∈ [currentPos - scrollDuration, currentPos]`。
  ///
  /// 二分找下界 + 线性扫到上界。复杂度 O(log N + visible)。
  Iterable<DanmakuItem> visibleAt(Duration position,
      {required Duration window}) sync* {
    final lowerMs = position.inMilliseconds - window.inMilliseconds;
    final upperMs = position.inMilliseconds;
    // 二分找第一个 position.inMilliseconds >= lowerMs 的 index
    var lo = 0;
    var hi = _items.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_items[mid].position.inMilliseconds < lowerMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo; i < _items.length; i++) {
      final ms = _items[i].position.inMilliseconds;
      if (ms > upperMs) break;
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

  @override
  void dispose() {
    // 当前无本地资源需要释放（_bucketLoader 持纯内存状态，items 是普通 List）。
    // 留此 override 作为 Task 7 overlay 等下游可能挂载的 listener / timer
    // 在 dispose 时取消的扩展点。
    super.dispose();
  }
}
