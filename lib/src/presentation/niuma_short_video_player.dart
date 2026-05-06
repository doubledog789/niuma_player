// lib/src/presentation/niuma_short_video_player.dart
import 'package:flutter/material.dart';

import '../domain/gesture_kind.dart';
import '../domain/niuma_short_video_theme.dart';
import '../domain/player_state.dart';
import 'niuma_danmaku_controller.dart';
import 'niuma_danmaku_overlay.dart';
import 'niuma_danmaku_scope.dart';
import 'niuma_gesture_layer.dart';
import 'niuma_player_controller.dart';
import 'niuma_player_view.dart';
import 'niuma_short_video_pause_indicator.dart';
import 'niuma_short_video_progress_bar.dart';
import 'niuma_short_video_scrub_label.dart';

/// 短视频外壳组件。与 [NiumaPlayer] 并列，专为竖屏短视频流（PageView 翻页）
/// 场景设计。
///
/// **不渲染：** ControlBar / 全屏按钮 / 弹幕 / 字幕 / 倍速画质选择器。
/// **手势：** 仅单击 toggle play/pause + 长按 2x。
class NiumaShortVideoPlayer extends StatefulWidget {
  /// 构造一个短视频播放器。
  const NiumaShortVideoPlayer({
    super.key,
    required this.controller,
    this.isActive = true,
    this.loop = true,
    this.muted = false,
    this.fit = BoxFit.cover,
    this.overlayBuilder,
    this.onSingleTap,
    this.theme,
    this.danmakuController,
    this.leftCenterBuilder,
  });

  /// 被驱动的 controller。
  final NiumaPlayerController controller;

  /// PageView 协调：true=应该播放、false=应该暂停。
  final bool isActive;

  /// 视频结束后是否循环（默认 true）。
  final bool loop;

  /// 是否静音首播（默认 false）。
  final bool muted;

  /// 视频画面填充方式（默认 cover）。
  final BoxFit fit;

  /// 业务在视频上方叠 UI 的 slot（爱心、评论、分享、用户信息等）。
  final Widget Function(BuildContext, NiumaPlayerValue)? overlayBuilder;

  /// 单击回调——null 时走默认 toggle play/pause。
  final void Function(NiumaPlayerController)? onSingleTap;

  /// 主题——null 时走 [NiumaShortVideoTheme.defaults]。
  final NiumaShortVideoTheme? theme;

  /// 可选弹幕 controller。传入即自动叠加 [NiumaDanmakuOverlay] 与注入
  /// [NiumaDanmakuScope]——同 [NiumaPlayer.danmakuController] 一致。
  ///
  /// **z-order：** 弹幕层位于视频画面之上、`overlayBuilder` 之下——
  /// 业务的爱心/评论/分享按钮永远盖在弹幕之上。
  final NiumaDanmakuController? danmakuController;

  /// 左中浮层 slot——业务可在此塞按钮（如全屏按钮）。
  /// 位置：左侧 12px 偏移，垂直居中。
  /// 典型用法：传 [NiumaShortVideoFullscreenButton] 实现抖音风全屏切换。
  ///
  /// 典型用法：`leftCenterBuilder: (ctx, c) => NiumaShortVideoFullscreenButton(controller: c, danmakuController: dc)` —— 全屏后弹幕也跟过去。
  final Widget Function(BuildContext, NiumaPlayerController)? leftCenterBuilder;

  @override
  State<NiumaShortVideoPlayer> createState() => _NiumaShortVideoPlayerState();
}

class _NiumaShortVideoPlayerState extends State<NiumaShortVideoPlayer> {
  late NiumaShortVideoTheme _theme;
  final ValueNotifier<bool> _isScrubbing = ValueNotifier(false);
  final ValueNotifier<Duration> _scrubPosition =
      ValueNotifier(Duration.zero);
  bool _autoPlayDone = false;
  // setLooping 在 controller 还没 initialize 时（_backend=null）会被 SDK
  // 静默吞——业务通常 fire-and-forget 调 initialize() 不 await，导致
  // initState 时 setLooping 调用无效。本标志让 _onValueChanged 在
  // phase 离开 idle/opening 后兜底再调一次。
  bool _loopingApplied = false;

  @override
  void initState() {
    super.initState();
    _theme = widget.theme ?? NiumaShortVideoTheme.defaults();
    // 用 native looping 实现"循环不闪烁"。iOS 上 video_player 走
    // AVPlayerLooper、Android 走自家原生 PlayerSession.setLooping，
    // 二者都在播完时直接重启 surface、不暴露 phase=ended——视觉上
    // 完全连续。Dart 层不再做 ended → seekTo(0) + play() 的模拟，
    // 否则全屏放大后能看到末帧→黑帧→reload 的几十毫秒断层（"前几帧
    // 抽搐"），并在 controller dispose 与 listener fire 的 race 里
    // 撞 'VideoPlayerController used after disposed'。
    //
    // 注意：业务通常 fire-and-forget 调 controller.initialize() 不 await，
    // 此时 _backend=null、setLooping 被静默吞——_onValueChanged 在
    // initialized=true 后做 once 兜底。
    widget.controller.setLooping(widget.loop);
    _loopingApplied = widget.controller.value.initialized;
    // isActive 决定首屏 play/pause：
    //   - true  → 当前页/默认页应自动播
    //   - false → PageView 上下相邻页应保持暂停，滑入瞬间不抖
    //
    // 注意 controller 可能还在 initialize（业务通常 fire-and-forget 调
    // controller.initialize() 不 await）。此时 play() 会被忽略——
    // [_onValueChanged] 监听 phase 变化，一旦达到 ready / paused
    // 就会兜底触发自动播。这里 postFrame 只对"已经 init 完的 controller"
    // 起作用（业务复用场景）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeAutoPlay();
      if (!widget.isActive) {
        widget.controller.pause();
      }
    });
    widget.controller.addListener(_onValueChanged);
    if (widget.muted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.setVolume(0);
      });
    }
  }

  @override
  void didUpdateWidget(covariant NiumaShortVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme != widget.theme) {
      _theme = widget.theme ?? NiumaShortVideoTheme.defaults();
    }
    if (oldWidget.loop != widget.loop) {
      widget.controller.setLooping(widget.loop);
      // 同 initState：可能此时仍未 init，标志重置等兜底
      _loopingApplied = widget.controller.value.initialized;
    }
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        widget.controller.play();
      } else {
        widget.controller.pause();
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onValueChanged);
    _isScrubbing.dispose();
    _scrubPosition.dispose();
    super.dispose();
  }

  /// 一旦 controller 进入 ready / paused（已 initialize 完），且本组件
  /// isActive=true，自动 play 一次。重复 phase 变化不再触发——业务/用户
  /// 后续手动 pause 不会被复活。
  void _maybeAutoPlay() {
    if (_autoPlayDone) return;
    if (!widget.isActive) return;
    final phase = widget.controller.value.phase;
    // ready：刚 init 完未播过；paused：业务可能复用已用过的 controller。
    if (phase == PlayerPhase.ready || phase == PlayerPhase.paused) {
      _autoPlayDone = true;
      widget.controller.play();
    }
  }

  void _onValueChanged() {
    _maybeAutoPlay();
    _maybeApplyLooping();
  }

  /// initState/didUpdateWidget 时 controller 可能还没 initialize 完——
  /// SDK 此时把 setLooping 静默吞。本方法在第一次拿到 initialized=true
  /// 后再调一次，使 native looping 真正生效。
  void _maybeApplyLooping() {
    if (_loopingApplied) return;
    if (!widget.controller.value.initialized) return;
    _loopingApplied = true;
    widget.controller.setLooping(widget.loop);
  }

  void _handleSingleTap() {
    if (widget.onSingleTap != null) {
      widget.onSingleTap!(widget.controller);
      return;
    }
    if (widget.controller.value.phase == PlayerPhase.playing) {
      widget.controller.pause();
    } else {
      widget.controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stack = Stack(
      fit: StackFit.expand,
      children: [
        // [1+2] 视频画面 + 单击/长按手势层（GestureLayer 在 child 上挂事件）
        NiumaGestureLayer(
          controller: widget.controller,
          enabled: true,
          disabledGestures: const {
            GestureKind.doubleTap,
            GestureKind.horizontalSeek,
            GestureKind.brightness,
            GestureKind.volume,
          },
          onTap: _handleSingleTap,
          // 用 ValueListenableBuilder 监听 controller.value.size，拿真实视频
          // 像素尺寸喂给 SizedBox——FittedBox 是矢量缩放、纹理不会糊。
          // 之前写 SizedBox(16, 9) 是 16x9 逻辑像素的微小 box，纹理被
          // 压成 16x9 再放大 25 倍 → 视频画面"花掉"。
          child: ValueListenableBuilder<NiumaPlayerValue>(
            valueListenable: widget.controller,
            builder: (ctx, value, _) {
              final w = value.size.width > 0 ? value.size.width : 1920.0;
              final h = value.size.height > 0 ? value.size.height : 1080.0;
              return FittedBox(
                fit: widget.fit,
                child: SizedBox(
                  width: w,
                  height: h,
                  child: NiumaPlayerView(
                    widget.controller,
                    aspectRatio: w / h,
                  ),
                ),
              );
            },
          ),
        ),
        // [2] 弹幕层（IgnorePointer：让 tap 透传给底下 GestureLayer 的单击 toggle）
        if (widget.danmakuController != null)
          Positioned.fill(
            child: IgnorePointer(
              child: NiumaDanmakuOverlay(
                video: widget.controller,
                danmaku: widget.danmakuController!,
              ),
            ),
          ),
        // [3] 粘性暂停图标
        Center(
          child: ValueListenableBuilder(
            valueListenable: widget.controller,
            builder: (ctx, value, _) {
              if (value.phase != PlayerPhase.paused) {
                return const SizedBox.shrink();
              }
              return NiumaShortVideoPauseIndicator(theme: _theme);
            },
          ),
        ),
        // [4] 业务 overlay
        if (widget.overlayBuilder != null)
          Positioned.fill(
            child: ValueListenableBuilder(
              valueListenable: widget.controller,
              builder: (ctx, value, _) => widget.overlayBuilder!(ctx, value),
            ),
          ),
        // [4.5] 左中 slot（典型：全屏按钮）
        if (widget.leftCenterBuilder != null)
          Positioned(
            left: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: widget.leftCenterBuilder!(context, widget.controller),
            ),
          ),
        // [5] 拖动时大字时间
        Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: _isScrubbing,
            builder: (ctx, scrubbing, _) {
              if (!scrubbing) return const SizedBox.shrink();
              return ValueListenableBuilder<Duration>(
                valueListenable: _scrubPosition,
                builder: (ctx, pos, _) => NiumaShortVideoScrubLabel(
                  position: pos,
                  duration: widget.controller.value.duration,
                  theme: _theme,
                ),
              );
            },
          ),
        ),
        // [6] 抖音式底部进度条
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: NiumaShortVideoProgressBar(
            controller: widget.controller,
            theme: _theme,
            onScrubStart: () => _isScrubbing.value = true,
            onScrubUpdate: (d) => _scrubPosition.value = d,
            onScrubEnd: () => _isScrubbing.value = false,
          ),
        ),
      ],
    );

    if (widget.danmakuController != null) {
      return NiumaDanmakuScope(
        controller: widget.danmakuController!,
        child: stack,
      );
    }
    return stack;
  }
}
