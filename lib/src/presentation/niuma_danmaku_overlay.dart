import 'package:flutter/widgets.dart';

import 'niuma_danmaku_controller.dart';
import 'niuma_danmaku_painter.dart';
import 'niuma_player_controller.dart';

/// 弹幕渲染层。可作为独立积木件直接 Stack 进自定义布局，也由 [NiumaPlayer]
/// 在传入 `danmakuController` 时自动接管。
///
/// 内部行为：
/// - 监听 [video] + [danmaku] merge 后的 listenable，每个变化触发 repaint
/// - 检测 |Δposition| > 1s 视为 seek，painter 自然下一帧从 visibleAt 重算
/// - settings.visible=false 时返回 SizedBox.expand（零绘）
/// - 跨入新桶时 fire-and-forget 触发 [NiumaDanmakuController.ensureLoadedFor]
class NiumaDanmakuOverlay extends StatefulWidget {
  /// 构造一个 overlay。
  const NiumaDanmakuOverlay({
    super.key,
    required this.video,
    required this.danmaku,
  });

  /// 视频 controller（提供 position 推送）。
  final NiumaPlayerController video;

  /// 弹幕 controller（数据源 + 配置）。
  final NiumaDanmakuController danmaku;

  @override
  State<NiumaDanmakuOverlay> createState() => _NiumaDanmakuOverlayState();
}

class _NiumaDanmakuOverlayState extends State<NiumaDanmakuOverlay> {
  late NiumaDanmakuPainter _painter;
  Listenable? _merged;
  Duration _lastPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _wirePainter();
    widget.video.addListener(_onVideoTick);
  }

  void _wirePainter() {
    _merged = Listenable.merge(<Listenable>[widget.video, widget.danmaku]);
    _painter = NiumaDanmakuPainter(
      danmaku: widget.danmaku,
      positionProvider: () => widget.video.value.position,
      repaint: _merged,
    );
  }

  void _onVideoTick() {
    final pos = widget.video.value.position;
    final delta = (pos - _lastPosition).abs();
    if (delta > const Duration(seconds: 1)) {
      // 大幅 seek：fire-and-forget 触发当前桶 lazy load
      widget.danmaku.ensureLoadedFor(pos);
    } else {
      // 小幅推进：检测桶切换
      final settings = widget.danmaku.settings;
      final cur =
          pos.inMilliseconds ~/ settings.bucketSize.inMilliseconds;
      final last =
          _lastPosition.inMilliseconds ~/ settings.bucketSize.inMilliseconds;
      if (cur != last) {
        widget.danmaku.ensureLoadedFor(pos);
      }
    }
    _lastPosition = pos;
  }

  @override
  void didUpdateWidget(covariant NiumaDanmakuOverlay old) {
    super.didUpdateWidget(old);
    if (old.video != widget.video || old.danmaku != widget.danmaku) {
      old.video.removeListener(_onVideoTick);
      _wirePainter();
      widget.video.addListener(_onVideoTick);
    }
  }

  @override
  void dispose() {
    widget.video.removeListener(_onVideoTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.danmaku,
      builder: (ctx, _) {
        if (!widget.danmaku.settings.visible) {
          return const SizedBox.expand();
        }
        return CustomPaint(
          painter: _painter,
          size: Size.infinite,
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
