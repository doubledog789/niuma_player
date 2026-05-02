// lib/src/presentation/niuma_short_video_player.dart
import 'package:flutter/material.dart';

import '../domain/gesture_kind.dart';
import '../domain/niuma_short_video_theme.dart';
import '../domain/player_state.dart';
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

  /// 左中浮层 slot——业务可在此塞按钮（如全屏按钮）。
  /// 位置：左侧 12px 偏移，垂直居中。
  /// 典型用法：传 [NiumaShortVideoFullscreenButton] 实现抖音风全屏切换。
  final Widget Function(BuildContext, NiumaPlayerController)? leftCenterBuilder;

  @override
  State<NiumaShortVideoPlayer> createState() => _NiumaShortVideoPlayerState();
}

class _NiumaShortVideoPlayerState extends State<NiumaShortVideoPlayer> {
  late NiumaShortVideoTheme _theme;
  final ValueNotifier<bool> _isScrubbing = ValueNotifier(false);
  final ValueNotifier<Duration> _scrubPosition =
      ValueNotifier(Duration.zero);

  @override
  void initState() {
    super.initState();
    _theme = widget.theme ?? NiumaShortVideoTheme.defaults();
    // isActive=false 启动时立即 pause（PageView 滑入瞬间不抖）
    if (!widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.pause();
      });
    }
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

  void _onValueChanged() {
    if (widget.loop &&
        widget.controller.value.phase == PlayerPhase.ended &&
        widget.isActive) {
      widget.controller.seekTo(Duration.zero);
      widget.controller.play();
    }
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
    return Stack(
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
          child: FittedBox(
            fit: widget.fit,
            child: SizedBox(
              width: 16,
              height: 9,
              child: NiumaPlayerView(widget.controller),
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
  }
}
