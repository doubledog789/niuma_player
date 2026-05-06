// lib/src/presentation/short_video/niuma_short_video_scrub_label.dart
import 'package:flutter/material.dart';

import 'package:niuma_player/src/domain/niuma_short_video_theme.dart';
import 'package:niuma_player/src/presentation/shared/glass_card.dart';
import 'package:niuma_player/src/presentation/shared/video_time_format.dart';

/// 拖动进度条时显示在视频中央的大字时间卡。
///
/// 显示格式：`mm:ss / mm:ss`（视频小于 1 小时）或 `H:mm:ss / H:mm:ss`。
class NiumaShortVideoScrubLabel extends StatelessWidget {
  /// 构造一个 scrub label。
  const NiumaShortVideoScrubLabel({
    super.key,
    required this.position,
    required this.duration,
    required this.theme,
  });

  /// 拖动到的位置。
  final Duration position;

  /// 视频总长。
  final Duration duration;

  /// 主题。
  final NiumaShortVideoTheme theme;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      color: theme.scrubLabelBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      radius: 14,
      child: Text(
        '${formatVideoTime(position)} / ${formatVideoTime(duration)}',
        style: TextStyle(
          color: theme.scrubLabelTextColor,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
