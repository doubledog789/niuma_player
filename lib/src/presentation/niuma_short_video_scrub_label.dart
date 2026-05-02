// lib/src/presentation/niuma_short_video_scrub_label.dart
import 'dart:ui';

import 'package:flutter/material.dart';

import '../domain/niuma_short_video_theme.dart';

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

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: theme.scrubLabelBackgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: Text(
            '${_fmt(position)} / ${_fmt(duration)}',
            style: TextStyle(
              color: theme.scrubLabelTextColor,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
