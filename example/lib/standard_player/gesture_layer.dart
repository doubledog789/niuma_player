// 手势层：把原始手势透传给 headless 核的 NiumaGestureController，
// 并监听它的 feedback 渲染中央 HUD。
//
// 关键边界：这一层不含任何播放/亮度/音量业务逻辑——这些都在核里的
// NiumaGestureController。widget 只负责「把手势几何量喂进去 + 把 HUD
// 状态画出来」。接入方换皮只动这里的渲染，不动核。
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// 透明手势捕获层 + 中央 HUD。
class GestureLayer extends StatelessWidget {
  /// 构造手势层。[gesture] 由上层（StandardPlayer）创建并负责 dispose；
  /// [onTap] 用于单击切控件显隐。
  const GestureLayer({
    super.key,
    required this.gesture,
    required this.onTap,
  });

  /// headless 核的手势编排器。
  final NiumaGestureController gesture;

  /// 单击回调（切控件显隐）。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 用 LayoutBuilder 拿到手势区尺寸，pan 时透传给核（核需要尺寸做
        // 左右半屏判定 + 位移归一）。
        LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onDoubleTap: gesture.onDoubleTap,
              onLongPressStart: (_) => gesture.onLongPressStart(),
              onLongPressEnd: (_) => gesture.onLongPressEnd(),
              onPanStart: (d) => gesture.onPanStart(d.localPosition),
              onPanUpdate: (d) => gesture.onPanUpdate(d.localPosition, size),
              onPanEnd: (_) => gesture.onPanEnd(),
            );
          },
        ),
        // HUD：监听核的 feedback，非空时画在屏幕中央。IgnorePointer 让它
        // 不拦截手势。
        IgnorePointer(
          child: ValueListenableBuilder<GestureFeedbackState?>(
            valueListenable: gesture.feedback,
            builder: (context, state, _) {
              if (state == null) return const SizedBox.shrink();
              return Center(child: _Hud(state: state));
            },
          ),
        ),
      ],
    );
  }
}

/// HUD 卡片：图标 + 文字 + 细进度条。
class _Hud extends StatelessWidget {
  const _Hud({required this.state});

  final GestureFeedbackState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(state.hudIcon), color: Colors.white, size: 32),
          if (state.label != null) ...[
            const SizedBox(height: 8),
            Text(
              state.label!,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              value: state.progress.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// 核只产出语义 [GestureHudIcon]；这里把它映射到 material [IconData]。
  /// 接入方可换成自家 SVG / 图标资源。
  IconData _iconFor(GestureHudIcon? icon) {
    switch (icon) {
      case GestureHudIcon.play:
        return Icons.play_arrow;
      case GestureHudIcon.pause:
        return Icons.pause;
      case GestureHudIcon.speed:
        return Icons.fast_forward;
      case GestureHudIcon.seekForward:
        return Icons.fast_forward;
      case GestureHudIcon.seekBackward:
        return Icons.fast_rewind;
      case GestureHudIcon.brightness:
        return Icons.brightness_6;
      case GestureHudIcon.volume:
        return Icons.volume_up;
      case GestureHudIcon.volumeMute:
        return Icons.volume_off;
      case null:
        return Icons.info_outline;
    }
  }
}
