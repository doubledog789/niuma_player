// lib/src/domain/niuma_short_video_theme.dart
import 'package:flutter/material.dart';

/// `NiumaShortVideoPlayer` 主题配置。
///
/// 与 [NiumaPlayerTheme] 平行：短视频组件永远以 root 形式出现，不会被多层
/// 嵌套，所以本类不走 `InheritedWidget`，直接通过 `theme` 字段传入。
@immutable
class NiumaShortVideoTheme {
  /// 所有字段均为必填——通常使用 [NiumaShortVideoTheme.defaults] 而非直接构造。
  const NiumaShortVideoTheme({
    required this.progressIdleHeight,
    required this.progressActiveHeight,
    required this.progressPlayedColor,
    required this.progressTrackColor,
    required this.progressBufferedColor,
    required this.progressThumbColor,
    required this.progressThumbRadius,
    required this.pauseIndicatorBackgroundColor,
    required this.pauseIndicatorIconColor,
    required this.pauseIndicatorSize,
    required this.pauseIndicatorIconSize,
    required this.scrubLabelTextColor,
    required this.scrubLabelBackgroundColor,
  });

  /// 文档默认值（抖音风）。
  ///
  /// 每次调用分配新实例——默认色含 [Color.withValues] 调用，
  /// 无法 const。host 可以在 build 之外缓存实例避免重复分配。
  factory NiumaShortVideoTheme.defaults() => NiumaShortVideoTheme(
        progressIdleHeight: 1.5,
        progressActiveHeight: 3.5,
        progressPlayedColor: Colors.white,
        progressTrackColor: Colors.white.withValues(alpha: 0.18),
        progressBufferedColor: Colors.white.withValues(alpha: 0.3),
        progressThumbColor: Colors.white,
        progressThumbRadius: 6.0,
        pauseIndicatorBackgroundColor: Colors.black.withValues(alpha: 0.5),
        pauseIndicatorIconColor: Colors.white,
        pauseIndicatorSize: 56,
        pauseIndicatorIconSize: 56,
        scrubLabelTextColor: Colors.white,
        scrubLabelBackgroundColor: Colors.black.withValues(alpha: 0.55),
      );

  /// 进度条 idle 状态的高度（默认 1.5）。
  final double progressIdleHeight;

  /// 进度条 scrubbing 状态的高度（默认 3.5）。
  final double progressActiveHeight;

  /// 已播放部分填充色（默认白）。
  final Color progressPlayedColor;

  /// 进度条背景轨道色（默认 白@0.18）。
  final Color progressTrackColor;

  /// 缓冲区填充色（默认 白@0.3）。
  final Color progressBufferedColor;

  /// 拖动手柄颜色（默认白）。
  final Color progressThumbColor;

  /// 拖动手柄半径（默认 6.0）。
  final double progressThumbRadius;

  /// 中央暂停图标背景圆色（默认 黑@0.5）。
  final Color pauseIndicatorBackgroundColor;

  /// 中央暂停图标的三角图标色（默认白）。
  final Color pauseIndicatorIconColor;

  /// 中央暂停图标的容器尺寸（默认 96）。
  final double pauseIndicatorSize;

  /// 中央暂停图标的内部 play_arrow 字号（默认 56）。
  final double pauseIndicatorIconSize;

  /// 拖动时大字时间卡的文本颜色（默认白）。
  final Color scrubLabelTextColor;

  /// 拖动时大字时间卡的背景色（默认 黑@0.55）。
  final Color scrubLabelBackgroundColor;

  /// 返回字段更新后的新实例。
  NiumaShortVideoTheme copyWith({
    double? progressIdleHeight,
    double? progressActiveHeight,
    Color? progressPlayedColor,
    Color? progressTrackColor,
    Color? progressBufferedColor,
    Color? progressThumbColor,
    double? progressThumbRadius,
    Color? pauseIndicatorBackgroundColor,
    Color? pauseIndicatorIconColor,
    double? pauseIndicatorSize,
    double? pauseIndicatorIconSize,
    Color? scrubLabelTextColor,
    Color? scrubLabelBackgroundColor,
  }) =>
      NiumaShortVideoTheme(
        progressIdleHeight: progressIdleHeight ?? this.progressIdleHeight,
        progressActiveHeight: progressActiveHeight ?? this.progressActiveHeight,
        progressPlayedColor: progressPlayedColor ?? this.progressPlayedColor,
        progressTrackColor: progressTrackColor ?? this.progressTrackColor,
        progressBufferedColor:
            progressBufferedColor ?? this.progressBufferedColor,
        progressThumbColor: progressThumbColor ?? this.progressThumbColor,
        progressThumbRadius: progressThumbRadius ?? this.progressThumbRadius,
        pauseIndicatorBackgroundColor: pauseIndicatorBackgroundColor ??
            this.pauseIndicatorBackgroundColor,
        pauseIndicatorIconColor:
            pauseIndicatorIconColor ?? this.pauseIndicatorIconColor,
        pauseIndicatorSize: pauseIndicatorSize ?? this.pauseIndicatorSize,
        pauseIndicatorIconSize:
            pauseIndicatorIconSize ?? this.pauseIndicatorIconSize,
        scrubLabelTextColor: scrubLabelTextColor ?? this.scrubLabelTextColor,
        scrubLabelBackgroundColor:
            scrubLabelBackgroundColor ?? this.scrubLabelBackgroundColor,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NiumaShortVideoTheme) return false;
    return progressIdleHeight == other.progressIdleHeight &&
        progressActiveHeight == other.progressActiveHeight &&
        progressPlayedColor == other.progressPlayedColor &&
        progressTrackColor == other.progressTrackColor &&
        progressBufferedColor == other.progressBufferedColor &&
        progressThumbColor == other.progressThumbColor &&
        progressThumbRadius == other.progressThumbRadius &&
        pauseIndicatorBackgroundColor == other.pauseIndicatorBackgroundColor &&
        pauseIndicatorIconColor == other.pauseIndicatorIconColor &&
        pauseIndicatorSize == other.pauseIndicatorSize &&
        pauseIndicatorIconSize == other.pauseIndicatorIconSize &&
        scrubLabelTextColor == other.scrubLabelTextColor &&
        scrubLabelBackgroundColor == other.scrubLabelBackgroundColor;
  }

  @override
  int get hashCode => Object.hash(
        progressIdleHeight,
        progressActiveHeight,
        progressPlayedColor,
        progressTrackColor,
        progressBufferedColor,
        progressThumbColor,
        progressThumbRadius,
        pauseIndicatorBackgroundColor,
        pauseIndicatorIconColor,
        pauseIndicatorSize,
        pauseIndicatorIconSize,
        scrubLabelTextColor,
        scrubLabelBackgroundColor,
      );
}
