import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ImageProvider;

/// 一条 WebVTT thumbnail cue：起止时间 + sprite URL + 裁剪矩形。
@immutable
class WebVttCue {
  /// 创建一条 thumbnail cue。
  const WebVttCue({
    required this.start,
    required this.end,
    required this.spriteUrl,
    required this.region,
  });

  /// cue 的起始播放时间（含）。
  final Duration start;

  /// cue 的结束播放时间（不含）。
  final Duration end;

  /// sprite 图引用（可能是相对路径，需结合 VTT 文件 baseUrl 解析）。
  final String spriteUrl;

  /// 在 sprite 图内的裁剪矩形（像素坐标）。
  final Rect region;

  /// 判断 [position] 是否落在 `[start, end)` 内。
  bool contains(Duration position) =>
      position >= start && position < end;

  @override
  bool operator ==(Object other) =>
      other is WebVttCue &&
      start == other.start &&
      end == other.end &&
      spriteUrl == other.spriteUrl &&
      region == other.region;

  @override
  int get hashCode => Object.hash(start, end, spriteUrl, region);
}

/// `controller.thumbnailFor(...)` 的返回值：图片提供者 + 在原图里的裁剪矩形。
@immutable
class ThumbnailFrame {
  /// 创建一个 thumbnail frame。
  const ThumbnailFrame({required this.image, required this.region});

  /// sprite 图的 [ImageProvider]（通常是 [NetworkImage]）。
  final ImageProvider image;

  /// 在 sprite 图内的裁剪矩形（像素坐标）。
  final Rect region;
}
