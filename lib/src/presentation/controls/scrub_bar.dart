import 'package:flutter/material.dart';

import '../../domain/player_state.dart';
import '../niuma_fullscreen_page.dart';
import '../niuma_player_controller.dart';
import '../niuma_player_theme.dart';
import '../niuma_scrub_preview.dart';

/// B 站风格密集进度条。
///
/// 特点：
/// 1. **三层填充**：背景 track（半透明灰）+ 已缓冲 fill（更深的灰）+
///    active fill（主题 `accentColor`，默认走 `Theme.of` primary）。
/// 2. **thumb 圆点**：静止半径 [NiumaPlayerTheme.scrubBarThumbRadius]，
///    拖动 / hover 半径 [NiumaPlayerTheme.scrubBarThumbRadiusActive]。
/// 3. **原始 pointer 路由**：用 [Listener] 而非 [GestureDetector]——避开
///    GestureDetector arena 的 tap/drag 仲裁延迟，按下即响应。
/// 4. **缩略图预览**：仅当 `controller.source.thumbnailVtt != null` 时才
///    挂 [NiumaScrubPreview]，节省屏幕空间和 build 开销。
/// 5. **commit 模型**：pointer move 期间只更新本地 `_scrubMs`、不下发；
///    pointer up 才调 [NiumaPlayerController.seekTo]，避免拖动过程中
///    触发大量 seek。
class ScrubBar extends StatefulWidget {
  /// 创建一个 [ScrubBar]。
  const ScrubBar({super.key, required this.controller, this.chapters});

  /// 该进度条观察 / 控制的 player controller。
  final NiumaPlayerController controller;

  /// 可选的章节时间点列表。非 null 时在进度条上叠加对应位置的细线标记。
  ///
  /// 每个 [Duration] 对应进度条上方一根 1px 宽、5px 高的白线（颜色由
  /// [NiumaPlayerTheme.chapterMarkColor] 控制）。超出 duration 范围的
  /// 时间点不渲染。标记外层 Positioned 带 `ValueKey('scrub-chapter-mark-$i')` 供测试查找。
  final List<Duration>? chapters;

  @override
  State<ScrubBar> createState() => _ScrubBarState();
}

class _ScrubBarState extends State<ScrubBar> {
  /// 拖动中的目标位置（毫秒）；`null` 表示不在拖动中。
  double? _scrubMs;

  bool get _scrubbing => _scrubMs != null;

  /// inline 状态不显示 VTT 缩略图预览（仅全屏沉浸式拖动需要）——
  /// 通过检测当前 BuildContext 是否在 [NiumaFullscreenScope] 内决定。
  bool get _hasThumbnail =>
      widget.controller.source.thumbnailVtt != null &&
      NiumaFullscreenScope.maybeOf(context) != null;

  /// 进度条本体的高度——足以容纳"拖动 thumb"圆点（thumbRadiusActive=9 → 18px
  /// 直径）和上下安全区。如果调用方需要更大点击区，外面包 [SizedBox] 即可。
  double _hostHeight() {
    final theme = NiumaPlayerTheme.of(context);
    return theme.scrubBarThumbRadiusActive * 2 + 8;
  }

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    final accent = theme.accentColor ?? Theme.of(context).colorScheme.primary;

    return ValueListenableBuilder<NiumaPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final durMs = value.duration.inMilliseconds.toDouble();
        final hasDuration = durMs > 0;
        final positionMs = _scrubMs ?? value.position.inMilliseconds.toDouble();
        final bufMs = value.bufferedPosition.inMilliseconds.toDouble();
        final progress =
            hasDuration ? (positionMs / durMs).clamp(0.0, 1.0) : 0.0;
        final bufferedProgress =
            hasDuration ? (bufMs / durMs).clamp(0.0, 1.0) : 0.0;

        return SizedBox(
          height: _hostHeight(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              // PiP 小窗 / 折叠状态 width 可能为 0，避免下方 clamp(low, high) 在
              // high<low 时抛 Invalid argument。
              if (width <= 0) return const SizedBox.shrink();
              final thumbX = width * progress;
              final previewWidth = theme.thumbnailPreviewSize.width;
              final previewLeft = width >= previewWidth
                  ? (thumbX - previewWidth / 2).clamp(0.0, width - previewWidth)
                  : 0.0;

              double xToMs(double x) {
                final clamped = x.clamp(0.0, width);
                return hasDuration ? (clamped / width) * durMs : 0.0;
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // 缩略图悬浮预览：thumb 上方 8px。
                  if (_scrubbing && _hasThumbnail)
                    Positioned(
                      left: previewLeft,
                      bottom: theme.scrubBarThumbRadiusActive * 2 + 8,
                      child: IgnorePointer(
                        child: NiumaScrubPreview(
                          controller: widget.controller,
                          scrubPosition:
                              Duration(milliseconds: positionMs.toInt()),
                        ),
                      ),
                    ),
                  // 章节标记：在进度条轨道上方渲染细线。
                  if (widget.chapters != null && hasDuration)
                    for (var ci = 0; ci < widget.chapters!.length; ci++)
                      if (widget.chapters![ci].inMilliseconds > 0 &&
                          widget.chapters![ci].inMilliseconds <
                              value.duration.inMilliseconds)
                        Positioned(
                          key: ValueKey('scrub-chapter-mark-$ci'),
                          left: (widget.chapters![ci].inMilliseconds / durMs) *
                              width,
                          top: constraints.maxHeight / 2 -
                              theme.scrubBarHeight / 2 -
                              1,
                          child: IgnorePointer(
                            child: Container(
                              width: 1,
                              height: theme.scrubBarHeight + 2,
                              color: theme.chapterMarkColor,
                            ),
                          ),
                        ),
                  // 原始 pointer 路由：不进 GestureDetector arena。
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: hasDuration
                        ? (e) {
                            setState(() {
                              _scrubMs = xToMs(e.localPosition.dx);
                            });
                          }
                        : null,
                    onPointerMove: hasDuration
                        ? (e) {
                            setState(() {
                              _scrubMs = xToMs(e.localPosition.dx);
                            });
                          }
                        : null,
                    onPointerUp: hasDuration
                        ? (_) {
                            final ms = _scrubMs;
                            if (ms != null) {
                              widget.controller
                                  .seekTo(Duration(milliseconds: ms.toInt()));
                            }
                            setState(() => _scrubMs = null);
                          }
                        : null,
                    onPointerCancel: hasDuration
                        ? (_) {
                            setState(() => _scrubMs = null);
                          }
                        : null,
                    child: CustomPaint(
                      size: Size(width, constraints.maxHeight),
                      painter: _ScrubBarPainter(
                        progress: progress,
                        bufferedProgress: bufferedProgress,
                        activeColor: accent,
                        bufferedColor: theme.bufferedFillColor ??
                            theme.iconColor.withValues(alpha: 0.4),
                        trackColor: theme.iconColor.withValues(alpha: 0.25),
                        thumbColor: accent,
                        trackHeight: theme.scrubBarHeight,
                        thumbRadius: _scrubbing
                            ? theme.scrubBarThumbRadiusActive
                            : theme.scrubBarThumbRadius,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ScrubBarPainter extends CustomPainter {
  _ScrubBarPainter({
    required this.progress,
    required this.bufferedProgress,
    required this.activeColor,
    required this.bufferedColor,
    required this.trackColor,
    required this.thumbColor,
    required this.trackHeight,
    required this.thumbRadius,
  });

  final double progress;
  final double bufferedProgress;
  final Color activeColor;
  final Color bufferedColor;
  final Color trackColor;
  final Color thumbColor;
  final double trackHeight;
  final double thumbRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackTop = centerY - trackHeight / 2;
    final radius = Radius.circular(trackHeight / 2);

    // 背景 track
    canvas.drawRRect(
      RRect.fromLTRBR(0, trackTop, size.width, trackTop + trackHeight, radius),
      Paint()..color = trackColor,
    );

    // buffered fill
    if (bufferedProgress > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          0,
          trackTop,
          size.width * bufferedProgress,
          trackTop + trackHeight,
          radius,
        ),
        Paint()..color = bufferedColor,
      );
    }

    // active fill
    if (progress > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          0,
          trackTop,
          size.width * progress,
          trackTop + trackHeight,
          radius,
        ),
        Paint()..color = activeColor,
      );
    }

    // thumb 圆点
    canvas.drawCircle(
      Offset(size.width * progress, centerY),
      thumbRadius,
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(covariant _ScrubBarPainter old) =>
      old.progress != progress ||
      old.bufferedProgress != bufferedProgress ||
      old.activeColor != activeColor ||
      old.bufferedColor != bufferedColor ||
      old.trackColor != trackColor ||
      old.thumbColor != thumbColor ||
      old.trackHeight != trackHeight ||
      old.thumbRadius != thumbRadius;
}
