import 'package:flutter/material.dart';

import 'niuma_player_controller.dart';
import 'niuma_player_theme.dart';
import 'niuma_thumbnail_view.dart';

/// 进度条悬浮缩略图预览。
///
/// 输入一个播放位置 [scrubPosition]，从 [controller] 上调
/// [NiumaPlayerController.thumbnailFor] 取出 [ThumbnailFrame]，用
/// [NiumaThumbnailView] 渲染成 [size] 所声明的目标尺寸；可选的时间
/// 标签 [showTime]（默认 `true`）在缩略图下方画一行 `mm:ss` 文字。
///
/// 当 controller 还没加载到 thumbnailVtt（[NiumaPlayerController.thumbnailFor]
/// 返回 `null`）时，本 widget 直接返回 [SizedBox.shrink]，不占布局空间——
/// ScrubBar 上层根据 source.thumbnailVtt 是否声明再决定是否挂载本组件。
///
/// 颜色 / 默认尺寸 / 文字样式从 [NiumaPlayerTheme.of] 读取，调用方
/// 通过把 [NiumaPlayerThemeData] 注入祖先来覆盖。
class NiumaScrubPreview extends StatelessWidget {
  /// 创建一个 [NiumaScrubPreview]。
  const NiumaScrubPreview({
    super.key,
    required this.controller,
    required this.scrubPosition,
    this.size,
    this.showTime = true,
  });

  /// 提供 [NiumaPlayerController.thumbnailFor] 的 controller。
  final NiumaPlayerController controller;

  /// 当前要预览的播放位置。
  final Duration scrubPosition;

  /// 缩略图目标尺寸。`null` 时使用主题中的
  /// [NiumaPlayerTheme.thumbnailPreviewSize]。
  final Size? size;

  /// 是否在缩略图下方渲染 `mm:ss` 时间标签。默认 `true`。
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final frame = controller.thumbnailFor(scrubPosition);
    if (frame == null) return const SizedBox.shrink();

    final theme = NiumaPlayerTheme.of(context);
    final s = size ?? theme.thumbnailPreviewSize;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: s.width,
          height: s.height,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.white70),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: NiumaThumbnailView(
            frame: frame,
            width: s.width,
            height: s.height,
          ),
        ),
        if (showTime) ...[
          const SizedBox(height: 4),
          Text(
            _formatTime(scrubPosition),
            style: theme.timeTextStyle,
          ),
        ],
      ],
    );
  }
}

String _formatTime(Duration d) {
  final s = d.inSeconds;
  final mm = (s ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}
