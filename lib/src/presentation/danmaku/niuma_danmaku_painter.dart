import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'package:niuma_player/src/orchestration/danmaku_models.dart';
import 'package:niuma_player/src/orchestration/danmaku_track_allocator.dart';
import 'package:niuma_player/src/presentation/danmaku/niuma_danmaku_controller.dart';

/// 弹幕渲染器。每帧根据当前 video position 计算可见 items 并 draw。
///
/// **不变量：**
/// - paint() 期间不修改 controller / 不 notifyListeners
/// - TextPainter 走 LRU cache（key = (text, fontSize, color)），上限 256 条
/// - 每帧 paint 开头 [DanmakuTrackAllocator.clear]：first-fit 必须从干净
///   状态出发，否则上一帧残留的 slot 会误导本帧轨道占用判断
///
/// 本类是 niuma_player 内部使用，**不导出**。Task 7 [NiumaDanmakuOverlay]
/// 实例化并把 painter 喂给 CustomPaint。
class NiumaDanmakuPainter extends CustomPainter {
  /// 构造一个 painter。
  ///
  /// [danmaku]：数据源（items + settings）。
  /// [positionProvider]：实时拿 video position（避免 painter 直接持 video controller）。
  /// [repaint]：painter 监听的 [Listenable]，通常是 video + danmaku 的 merge。
  NiumaDanmakuPainter({
    required this.danmaku,
    required this.positionProvider,
    super.repaint,
  });

  /// 数据源。
  final NiumaDanmakuController danmaku;

  /// 实时拿当前播放进度的回调。
  final Duration Function() positionProvider;

  final DanmakuTrackAllocator _allocator = DanmakuTrackAllocator();

  static const int _maxCache = 256;
  final LinkedHashMap<_TextKey, TextPainter> _cache =
      LinkedHashMap<_TextKey, TextPainter>();

  TextPainter _measure(String text, double fontSize, Color color) {
    final key = _TextKey(text, fontSize, color);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // 重新放到末尾 = 最近访问
      return hit;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          shadows: const [Shadow(blurRadius: 1, color: Color(0xFF000000))],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _cache[key] = tp;
    if (_cache.length > _maxCache) {
      _cache.remove(_cache.keys.first);
    }
    return tp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final settings = danmaku.settings;
    if (!settings.visible) return;

    final position = positionProvider();
    final fontScale = settings.fontScale;
    // 用基准字号 20 估算 rowHeight，确保大字号不重叠
    final rowHeight = 20 * fontScale * 1.4;

    _allocator.resize(
      width: size.width,
      height: size.height,
      rowHeight: rowHeight,
      areaPercent: settings.displayAreaPercent,
    );
    _allocator.clear();

    final window = settings.scrollDuration > settings.fixedDuration
        ? settings.scrollDuration
        : settings.fixedDuration;
    final candidates = danmaku.visibleAt(position, window: window);
    final nowMs = position.inMilliseconds;

    for (final it in candidates) {
      final fontSize = it.fontSize * fontScale;
      final color = it.color.withValues(
        alpha: it.color.a * settings.opacity,
      );
      final tp = _measure(it.text, fontSize, color);

      switch (it.mode) {
        case DanmakuMode.scroll:
          final row = _allocator.allocateScrollTrack(
            textWidth: tp.width,
            scrollDuration: settings.scrollDuration,
            screenWidth: size.width,
            nowMs: nowMs,
          );
          if (row < 0) continue;
          final spawnMs = it.position.inMilliseconds;
          final progress =
              ((nowMs - spawnMs) / settings.scrollDuration.inMilliseconds)
                  .clamp(0.0, 1.0);
          final x = size.width - (size.width + tp.width) * progress;
          final y = row * rowHeight;
          tp.paint(canvas, Offset(x, y));
        case DanmakuMode.topFixed:
          final row = _allocator.allocateTopFixedTrack(
            fixedDuration: settings.fixedDuration,
            nowMs: nowMs,
          );
          if (row < 0) continue;
          final x = (size.width - tp.width) / 2;
          final y = row * rowHeight;
          tp.paint(canvas, Offset(x, y));
        case DanmakuMode.bottomFixed:
          final row = _allocator.allocateBottomFixedTrack(
            fixedDuration: settings.fixedDuration,
            nowMs: nowMs,
          );
          if (row < 0) continue;
          final displayBottom = size.height * settings.displayAreaPercent;
          final x = (size.width - tp.width) / 2;
          final y = displayBottom - (row + 1) * rowHeight;
          tp.paint(canvas, Offset(x, y));
      }
    }
  }

  @override
  bool shouldRepaint(covariant NiumaDanmakuPainter oldDelegate) => true;
}

@immutable
class _TextKey {
  const _TextKey(this.text, this.fontSize, this.color);
  final String text;
  final double fontSize;
  final Color color;
  @override
  bool operator ==(Object other) =>
      other is _TextKey &&
      other.text == text &&
      other.fontSize == fontSize &&
      other.color == color;
  @override
  int get hashCode => Object.hash(text, fontSize, color);
}
