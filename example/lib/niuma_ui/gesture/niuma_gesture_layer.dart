import 'package:flutter/material.dart';

import 'package:niuma_player/niuma_player.dart';
import 'niuma_gesture_hud.dart';


/// HUD 自定义 builder 类型。
typedef GestureHudBuilder = Widget Function(
  BuildContext context,
  GestureFeedbackState state,
);

/// 视频手势层——5 项核心手势 + HUD 协调。
///
/// 默认仅在全屏页生效（通过 [enabled] 字段控制）；inline 场景由
/// `NiumaPlayer.gesturesEnabledInline` 决定 enabled。
///
/// 手势逻辑全部委托给 headless 核的 [NiumaGestureController]——本 widget 只把
/// `GestureDetector` 的回调透传过去、监听 controller 的 `feedback` 渲染 HUD。
///
/// 5 项手势：
/// - 双击 → controller.play/pause
/// - 长按 → 临时 2x，松手恢复
/// - 水平 pan → seek（松手才提交）
/// - 左半屏垂直 pan → 亮度（立即生效，节流 50ms）
/// - 右半屏垂直 pan → 音量（同上）
class NiumaGestureLayer extends StatefulWidget {
  /// 构造一个 gesture layer。
  const NiumaGestureLayer({
    super.key,
    required this.controller,
    this.disabledGestures = const {},
    this.hudBuilder,
    this.onTap,
    this.enabled = true,
    required this.child,
  });

  /// 被驱动的 controller。
  final NiumaPlayerController controller;

  /// 黑名单：不触发的手势类型。
  final Set<GestureKind> disabledGestures;

  /// HUD 自定义 builder。null = 用 [NiumaGestureHud] 默认。
  final GestureHudBuilder? hudBuilder;

  /// onTap 透传——M9 既有的"单击切控件显隐"通过这个保留行为。
  final VoidCallback? onTap;

  /// 整体是否启用。false = 仅透传 onTap，其他手势全部跳过。
  final bool enabled;

  /// 内层视频 view（NiumaPlayerView 等）。
  final Widget child;

  @override
  State<NiumaGestureLayer> createState() => _NiumaGestureLayerState();
}

class _NiumaGestureLayerState extends State<NiumaGestureLayer> {
  late final NiumaGestureController _gc;

  @override
  void initState() {
    super.initState();
    _gc = NiumaGestureController(
      widget.controller,
      disabledGestures: widget.disabledGestures,
    );
    _gc.initBrightness();
  }

  @override
  void dispose() {
    _gc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onTap?.call(),
            // doubleTap 被 disable 时传 null——让 GestureDetector 不再等双击
            // 消歧，单击立即 fire onTap（短视频里靠这个拿到即时单击 toggle）。
            onDoubleTap: (widget.enabled &&
                    !widget.disabledGestures.contains(GestureKind.doubleTap))
                ? _gc.onDoubleTap
                : null,
            onLongPressStart:
                widget.enabled ? (_) => _gc.onLongPressStart() : null,
            onLongPressEnd:
                widget.enabled ? (_) => _gc.onLongPressEnd() : null,
            onPanStart: widget.enabled
                ? (d) => _gc.onPanStart(d.localPosition)
                : null,
            onPanUpdate: widget.enabled
                ? (d) {
                    final size = context.size;
                    if (size != null) {
                      _gc.onPanUpdate(d.localPosition, size);
                    }
                  }
                : null,
            onPanEnd: widget.enabled ? (_) => _gc.onPanEnd() : null,
            child: widget.child,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<GestureFeedbackState?>(
              valueListenable: _gc.feedback,
              builder: (ctx, state, _) {
                if (state == null) return const SizedBox.shrink();
                return Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: widget.hudBuilder != null
                        ? KeyedSubtree(
                            key: ValueKey(state.kind),
                            child: widget.hudBuilder!(ctx, state),
                          )
                        : NiumaGestureHud(
                            key: ValueKey(state.kind),
                            state: state,
                          ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
