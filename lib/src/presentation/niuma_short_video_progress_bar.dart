// lib/src/presentation/niuma_short_video_progress_bar.dart
import 'package:flutter/material.dart';

import '../domain/niuma_short_video_theme.dart';
import '../domain/player_state.dart';
import 'niuma_player_controller.dart';

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

  static const double _hitAreaHeight = 24.0;

  void _onPointerDown(PointerDownEvent event, BoxConstraints constraints) {
    final width = constraints.maxWidth;
    if (width <= 0) return;
    final newProgress = (event.localPosition.dx / width).clamp(0.0, 1.0);
    setState(() {
      _scrubbing = true;
      _progress = newProgress;
      _wasPlayingBeforeScrub =
          widget.controller.value.phase == PlayerPhase.playing;
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
    setState(() => _progress = newProgress);
    widget.onScrubUpdate(_durationFromProgress(newProgress));
  }

  void _onPointerUp(PointerUpEvent _) => _finishScrub();
  void _onPointerCancel(PointerCancelEvent _) => _finishScrub();

  void _finishScrub() {
    if (!_scrubbing) return;
    final target = _durationFromProgress(_progress);
    widget.controller.seekTo(target);
    if (_wasPlayingBeforeScrub) widget.controller.play();
    widget.onScrubEnd();
    setState(() => _scrubbing = false);
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
                          // thumb
                          if (_scrubbing)
                            Positioned(
                              left: pos.clamp(0.0, 1.0) *
                                      constraints.maxWidth -
                                  widget.theme.progressThumbRadius,
                              top: -(widget.theme.progressThumbRadius -
                                  h / 2),
                              child: Container(
                                width: widget.theme.progressThumbRadius * 2,
                                height: widget.theme.progressThumbRadius * 2,
                                decoration: BoxDecoration(
                                  color: widget.theme.progressThumbColor,
                                  shape: BoxShape.circle,
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
