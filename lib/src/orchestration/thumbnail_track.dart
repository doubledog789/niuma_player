import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ImageProvider;

/// 一条 WebVTT thumbnail cue：起止时间 + sprite URL + 裁剪矩形。
///
/// 通常只通过 [WebVttParser.parseThumbnails] 的返回值消费，手工构造主要
/// 用于测试 mock。直接 new 一个 cue 时调用方需要自行保证 `start < end`、
/// region 内的坐标合法。
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
///
/// 两个 frame 相等当且仅当 `image` 是同一个 [ImageProvider] 实例（用 identity
/// 比较——同 URL 同 cache，[ThumbnailCache] 保证 dedup）且 `region` 相等。
/// 用 identity 比较 image 而不是 ==，是因为 [NetworkImage] 自身的 == 走 url，
/// 我们的 cache 已经按 URL 去重，identity 等价于 URL 等价但更便宜。
@immutable
class ThumbnailFrame {
  /// 创建一个 thumbnail frame。
  const ThumbnailFrame({required this.image, required this.region});

  /// sprite 图的 [ImageProvider]（通常是 [NetworkImage]）。
  final ImageProvider image;

  /// 在 sprite 图内的裁剪矩形（像素坐标）。
  final Rect region;

  @override
  bool operator ==(Object other) =>
      other is ThumbnailFrame &&
      identical(image, other.image) &&
      region == other.region;

  @override
  int get hashCode => Object.hash(identityHashCode(image), region);
}

/// 缩略图加载状态。
///
/// 状态机：
/// ```
///   none      ← source.thumbnailVtt 为 null（功能未启用）
///   idle      ← 已配置但 initialize() 还没跑完，加载未启动
///   loading   ← _loadThumbnailsIfAny 正在 fetch + 解析
///   ready     ← 解析完成（cues 列表可能为空，但解析成功）
///   failed    ← fetch 或解析抛过异常被静默吞，thumbnailFor 永远返回 null
/// ```
///
/// 状态变更**不会**触发 [NiumaPlayerController] 的 ValueNotifier 通知，
/// 也不通过 `controller.events` 流广播——避免和 player 自身的 value /
/// 事件混在一起。如果上层需要响应这个状态，可以：
/// 1. 在 build 时直接读 `controller.thumbnailLoadState`（适合一次性检查）；
/// 2. 围绕 player 自身的 events 做轮询（loading→ready 通常 < 100ms）；
/// 3. 简单 `setState` 后让 `thumbnailFor` 返回值自然反映"暂时还没好"。
///
/// 特别说明：解析返回**空** cue 列表（例如合法 WEBVTT 头但没有任何 cue）
/// 仍记 `ready`——解析本身成功，只是无内容。`thumbnailFor` 在
/// `_thumbnailCues.isEmpty` 时直接返回 null，调用方无需区分。
enum ThumbnailLoadState {
  /// 未配置 `source.thumbnailVtt`。功能未启用。
  none,

  /// 已配置但还没开始加载（`initialize` 没跑完）。
  idle,

  /// 正在 fetch / 解析。
  loading,

  /// 加载 / 解析完成。`thumbnailFor` 可能返回 frame 或 null（cue 不命中）。
  ready,

  /// 加载或解析失败（异常已被静默吞）。`thumbnailFor` 永远返回 null。
  failed,
}
