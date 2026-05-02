// lib/src/presentation/niuma_short_video_pause_indicator.dart
import 'package:flutter/material.dart';

import '../domain/niuma_short_video_theme.dart';

/// 短视频暂停态中央粘性图标。
///
/// 在 `phase=paused` 时由父组件挂上，`play()` 后立刻消失（无淡出，
/// 避免点击响应延迟感）。本组件不响应自身 hit-test，tap 透传给底下单击层。
class NiumaShortVideoPauseIndicator extends StatefulWidget {
  /// 构造一个暂停指示器。
  const NiumaShortVideoPauseIndicator({super.key, required this.theme});

  /// 主题。
  final NiumaShortVideoTheme theme;

  @override
  State<NiumaShortVideoPauseIndicator> createState() =>
      _NiumaShortVideoPauseIndicatorState();
}

class _NiumaShortVideoPauseIndicatorState
    extends State<NiumaShortVideoPauseIndicator> {
  double _scale = 0.8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _scale = 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: Container(
          width: widget.theme.pauseIndicatorSize,
          height: widget.theme.pauseIndicatorSize,
          decoration: BoxDecoration(
            color: widget.theme.pauseIndicatorBackgroundColor,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            color: widget.theme.pauseIndicatorIconColor,
            size: widget.theme.pauseIndicatorIconSize,
          ),
        ),
      ),
    );
  }
}
