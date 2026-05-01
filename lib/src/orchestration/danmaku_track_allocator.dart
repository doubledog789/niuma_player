import 'package:flutter/foundation.dart';

/// scroll/topFixed/bottomFixed 三模式各自独立的 first-fit 轨道分配器。
///
/// **不变量：**
/// - 同一 mode 内同一 row 不会被重叠占用
/// - 满轨道时分配返回 -1（caller 应丢弃该 item，不入队不阻塞）
class DanmakuTrackAllocator {
  /// 构造空分配器。使用前必须调一次 [resize]。
  DanmakuTrackAllocator();

  // scroll: row → 上一占用者快照（textWidth, spawnMs, scrollDurationMs, screenWidth）
  final List<_ScrollSlot?> _scroll = <_ScrollSlot?>[];
  // topFixed/bottomFixed: row → (spawnMs, durationMs)
  final List<_FixedSlot?> _top = <_FixedSlot?>[];
  final List<_FixedSlot?> _bottom = <_FixedSlot?>[];

  /// 当前可用 scroll 行数。
  int get scrollRowCount => _scroll.length;

  /// 当前可用 top 行数。
  int get topRowCount => _top.length;

  /// 当前可用 bottom 行数。
  int get bottomRowCount => _bottom.length;

  /// 重新计算 row 数。每次 build 尺寸变化或 settings.displayAreaPercent 变化时调用。
  ///
  /// scroll 行数 = floor(height * areaPercent / rowHeight)；
  /// top / bottom 各占一半。
  void resize({
    required double width,
    required double height,
    required double rowHeight,
    required double areaPercent,
  }) {
    final available = (height * areaPercent / rowHeight).floor();
    _resizeList(_scroll, available);
    _resizeList(_top, (available / 2).floor());
    _resizeList(_bottom, (available / 2).floor());
  }

  static void _resizeList<T>(List<T?> list, int target) {
    if (list.length == target) return;
    if (list.length < target) {
      list.addAll(List<T?>.filled(target - list.length, null, growable: true));
    } else {
      list.removeRange(target, list.length);
    }
  }

  /// 分配一个 scroll 轨道。返回 row index，满轨道返回 -1。
  ///
  /// 规则：上一占用者右边沿 < `screenWidth - safeMargin` 即让出。
  int allocateScrollTrack({
    required double textWidth,
    required Duration scrollDuration,
    required double screenWidth,
    required int nowMs,
    double safeMargin = 8,
  }) {
    for (var row = 0; row < _scroll.length; row++) {
      final slot = _scroll[row];
      if (slot == null) {
        _scroll[row] = _ScrollSlot(
          textWidth,
          nowMs,
          scrollDuration.inMilliseconds,
          screenWidth,
        );
        return row;
      }
      final elapsed = nowMs - slot.spawnMs;
      final progress = elapsed / slot.scrollDurationMs;
      if (progress >= 1) {
        _scroll[row] = _ScrollSlot(
          textWidth,
          nowMs,
          scrollDuration.inMilliseconds,
          screenWidth,
        );
        return row;
      }
      final rightEdge =
          slot.screenWidth - (slot.screenWidth + slot.textWidth) * progress + slot.textWidth;
      if (rightEdge < screenWidth - safeMargin) {
        _scroll[row] = _ScrollSlot(
          textWidth,
          nowMs,
          scrollDuration.inMilliseconds,
          screenWidth,
        );
        return row;
      }
    }
    return -1;
  }

  /// 分配一个 topFixed 轨道。返回 row index，满轨道返回 -1。
  int allocateTopFixedTrack({
    required Duration fixedDuration,
    required int nowMs,
  }) =>
      _allocateFixed(_top, fixedDuration.inMilliseconds, nowMs);

  /// 分配一个 bottomFixed 轨道。返回 row index，满轨道返回 -1。
  int allocateBottomFixedTrack({
    required Duration fixedDuration,
    required int nowMs,
  }) =>
      _allocateFixed(_bottom, fixedDuration.inMilliseconds, nowMs);

  static int _allocateFixed(List<_FixedSlot?> rows, int durationMs, int nowMs) {
    for (var row = 0; row < rows.length; row++) {
      final slot = rows[row];
      if (slot == null || nowMs - slot.spawnMs >= slot.durationMs) {
        rows[row] = _FixedSlot(nowMs, durationMs);
        return row;
      }
    }
    return -1;
  }

  /// 清空全部占用。seek / 模式切换 / 区域调整时调用。
  void clear() {
    for (var i = 0; i < _scroll.length; i++) {
      _scroll[i] = null;
    }
    for (var i = 0; i < _top.length; i++) {
      _top[i] = null;
    }
    for (var i = 0; i < _bottom.length; i++) {
      _bottom[i] = null;
    }
  }
}

@immutable
class _ScrollSlot {
  const _ScrollSlot(
    this.textWidth,
    this.spawnMs,
    this.scrollDurationMs,
    this.screenWidth,
  );

  /// 弹幕文本宽度（逻辑像素）。
  final double textWidth;

  /// 弹幕出现时刻（毫秒）。
  final int spawnMs;

  /// 滚动总时长（毫秒）。
  final int scrollDurationMs;

  /// 弹幕出现时屏幕宽度（逻辑像素）。
  final double screenWidth;
}

@immutable
class _FixedSlot {
  const _FixedSlot(this.spawnMs, this.durationMs);

  /// 固定弹幕出现时刻（毫秒）。
  final int spawnMs;

  /// 固定弹幕显示时长（毫秒）。
  final int durationMs;
}
