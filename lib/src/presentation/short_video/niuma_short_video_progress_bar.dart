// lib/src/presentation/short_video/niuma_short_video_progress_bar.dart
import 'package:flutter/material.dart';

import 'package:niuma_player/src/domain/niuma_short_video_theme.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_controller.dart';
import 'package:niuma_player/src/presentation/feedback/niuma_progress_thumb.dart';

/// 抖音式底部细线进度条。
///
/// idle 状态：1.5px 细线贴底
/// 触摸状态：变粗到 3.5px + 出现 thumb
/// 拖动期间：调用 [onScrubStart] / [onScrubUpdate] / [onScrubEnd]
/// 由父组件（NiumaShortVideoPlayer）订阅来管理 _isScrubbing notifier 和 scrubLabel 显示。
class NiumaShortVideoProgressBar extends StatefulWidget {
  /// 构造一个进度条。
  const NiumaShortVideoProgressBar({
    super.key,
    required this.controller,
    required this.theme,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  /// 被驱动的 controller。
  final NiumaPlayerController controller;

  /// 主题。
  final NiumaShortVideoTheme theme;

  /// 拖动开始时调用——父组件应：1) pause 控制器；2) 显示 scrubLabel。
  final VoidCallback onScrubStart;

  /// 拖动每帧调用，参数为当前拖动到的目标位置。
  final ValueChanged<Duration> onScrubUpdate;

  /// 拖动结束时调用——父组件应：1) seek 到目标位置；2) 恢复 play 状态；
  /// 3) 隐藏 scrubLabel。
  final VoidCallback onScrubEnd;

  @override
  State<NiumaShortVideoProgressBar> createState() =>
      _NiumaShortVideoProgressBarState();
}

class _NiumaShortVideoProgressBarState
    extends State<NiumaShortVideoProgressBar> {
  bool _scrubbing = false;
  double _progress = 0.0;
  bool _wasPlayingBeforeScrub = false;

  // 给 NiumaProgressThumb 算 seekDirection / seekSpeed。
  double? _lastProgress;
  DateTime? _lastProgressTime;
  int _seekDirection = 0;
  double _seekSpeed = 0;

  void _track(double newP, double widthPx) {
    final now = DateTime.now();
    final lastP = _lastProgress;
    final lastT = _lastProgressTime;
    if (lastP != null && lastT != null) {
      final dtMs = now.difference(lastT).inMilliseconds;
      if (dtMs > 0) {
        // 用像素差作为 speed 标尺，跟 NiumaProgressThumb 文档单位一致。
        _seekSpeed = ((newP - lastP).abs() * widthPx) / (dtMs / 100);
        _seekDirection = (newP - lastP) > 0 ? 1 : ((newP - lastP) < 0 ? -1 : 0);
      }
    }
    _lastProgress = newP;
    _lastProgressTime = now;
  }

  void _resetTrack() {
    _lastProgress = null;
    _lastProgressTime = null;
    _seekDirection = 0;
    _seekSpeed = 0;
  }

  static const double _hitAreaHeight = 24.0;

  void _onPointerDown(PointerDownEvent event, BoxConstraints constraints) {
    if (_scrubbing) return;
    final width = constraints.maxWidth;
    if (width <= 0) return;
    final newProgress = (event.localPosition.dx / width).clamp(0.0, 1.0);
    setState(() {
      _scrubbing = true;
      _progress = newProgress;
      _wasPlayingBeforeScrub =
          widget.controller.value.phase == PlayerPhase.playing;
      _track(newProgress, width);
    });
    widget.controller.pause();
    widget.onScrubStart();
    widget.onScrubUpdate(_durationFromProgress(_progress));
  }

  void _onPointerMove(PointerMoveEvent event, BoxConstraints constraints) {
    if (!_scrubbing) return;
    final width = constraints.maxWidth;
    if (width <= 0) return;
    final newProgress = (event.localPosition.dx / width).clamp(0.0, 1.0);
    setState(() {
      _progress = newProgress;
      _track(newProgress, width);
    });
    widget.onScrubUpdate(_durationFromProgress(newProgress));
  }

  void _onPointerUp(PointerUpEvent _) => _finishScrub();

  void _onPointerCancel(PointerCancelEvent _) {
    if (!_scrubbing) return;
    // 取消 = 不 seek，仅恢复 play 状态 + 通知 parent 隐藏 scrubLabel
    if (_wasPlayingBeforeScrub) widget.controller.play();
    widget.onScrubEnd();
    setState(() {
      _scrubbing = false;
      _resetTrack();
    });
  }

  void _finishScrub() {
    if (!_scrubbing) return;
    final target = _durationFromProgress(_progress);
    widget.controller.seekTo(target);
    if (_wasPlayingBeforeScrub) widget.controller.play();
    widget.onScrubEnd();
    setState(() {
      _scrubbing = false;
      _resetTrack();
    });
  }

  Duration _durationFromProgress(double p) {
    final dur = widget.controller.value.duration;
    return Duration(milliseconds: (dur.inMilliseconds * p).round());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (ctx, value, _) {
        final dur = value.duration.inMilliseconds;
        final pos = _scrubbing
            ? _progress
            : (dur > 0 ? value.position.inMilliseconds / dur : 0.0);
        final buffered = dur > 0
            ? value.bufferedPosition.inMilliseconds / dur
            : 0.0;
        final h = _scrubbing
            ? widget.theme.progressActiveHeight
            : widget.theme.progressIdleHeight;
        return SizedBox(
          height: _hitAreaHeight,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: LayoutBuilder(
              builder: (ctx, constraints) => Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _onPointerDown(e, constraints),
                onPointerMove: (e) => _onPointerMove(e, constraints),
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: SizedBox(
                  width: double.infinity,
                  height: _hitAreaHeight,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      constraints: BoxConstraints.tightFor(
                        width: constraints.maxWidth,
                        height: h,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // track
                          Container(color: widget.theme.progressTrackColor),
                          // buffered
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: buffered.clamp(0.0, 1.0),
                            child: Container(
                              color: widget.theme.progressBufferedColor,
                            ),
                          ),
                          // played
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: pos.clamp(0.0, 1.0),
                            child: Container(
                              color: widget.theme.progressPlayedColor,
                            ),
                          ),
                          // thumb：拖动期间换成牛马表情，按方向 / 速度切 5 表情。
                          if (_scrubbing)
                            Positioned(
                              left: pos.clamp(0.0, 1.0) *
                                      constraints.maxWidth -
                                  16,
                              top: -(16 - h / 2),
                              child: IgnorePointer(
                                child: NiumaProgressThumb(
                                  progress: pos,
                                  isPlaying: value.isPlaying,
                                  isDragging: true,
                                  seekDirection: _seekDirection,
                                  seekSpeed: _seekSpeed,
                                  size: 32,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
