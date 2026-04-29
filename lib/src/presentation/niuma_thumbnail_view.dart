import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../orchestration/thumbnail_track.dart';

/// 把 [ThumbnailFrame] 渲染到屏幕上的助手 widget。
///
/// 内部封装：
///   1. [ImageStream] 解析（含 *synchronousCall* 防御——同步触发的 listener
///      会在 build / initState 阶段重入，直接 setState 会撞 'framework is locked'，
///      所以走 [SchedulerBinding.addPostFrameCallback] 延后）；
///   2. sprite crop 渲染（[CustomPaint] + [Canvas.drawImageRect]）；
///   3. frame 切换时自动 detach 旧 [ImageStreamListener] 重新解析新 image。
///
/// 输入 `null` 时显示 [placeholder]（默认空白）；image 还在加载时显示 [loadingBuilder]
/// 默认（也是空白），加载失败显示 [errorBuilder]（默认空白）。
///
/// 典型用法：
/// ```dart
/// final frame = controller.thumbnailFor(scrubPosition);
/// NiumaThumbnailView(
///   frame: frame,
///   width: 160,
///   height: 90,
/// );
/// ```
class NiumaThumbnailView extends StatefulWidget {
  /// 创建一个 thumbnail view。
  const NiumaThumbnailView({
    super.key,
    required this.frame,
    this.width,
    this.height,
    this.filterQuality = FilterQuality.medium,
    this.placeholder,
    this.loadingBuilder,
    this.errorBuilder,
  });

  /// 当前要显示的 frame；null 时显示 [placeholder]。
  final ThumbnailFrame? frame;

  /// 显示宽度。null 时占满父布局。
  final double? width;

  /// 显示高度。null 时占满父布局。
  final double? height;

  /// 绘制 sprite crop 时的 [FilterQuality]。默认 medium。
  final FilterQuality filterQuality;

  /// frame 为 null 时显示的 widget；默认 [SizedBox.shrink]（空白）。
  final Widget? placeholder;

  /// frame 已就绪但 sprite 图还在解码 / 网络下载时显示的 widget；
  /// 默认 [SizedBox.shrink]。
  final Widget Function(BuildContext context)? loadingBuilder;

  /// sprite 图加载失败时显示的 widget；默认 [SizedBox.shrink]。
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  State<NiumaThumbnailView> createState() => _NiumaThumbnailViewState();
}

class _NiumaThumbnailViewState extends State<NiumaThumbnailView> {
  ui.Image? _resolved;
  Object? _error;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolveCurrent();
  }

  @override
  void didUpdateWidget(covariant NiumaThumbnailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldImage = oldWidget.frame?.image;
    final newImage = widget.frame?.image;
    if (!identical(oldImage, newImage)) {
      _detach();
      _resolved = null;
      _error = null;
      _resolveCurrent();
    }
  }

  void _resolveCurrent() {
    final frame = widget.frame;
    if (frame == null) return;
    final stream = frame.image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, synchronousCall) {
        if (!mounted) return;
        if (synchronousCall) {
          // 图已缓存 → listener 在 addListener 内同步 fire；此时仍可能在
          // build / initState 阶段，直接 setState 会触发 'framework is locked'。
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _resolved = info.image);
          });
        } else {
          setState(() => _resolved = info.image);
        }
      },
      onError: (Object e, StackTrace? st) {
        if (!mounted) return;
        debugPrint('[niuma_player] NiumaThumbnailView image error: $e');
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _error = e);
        });
      },
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.frame;
    if (frame == null) {
      return widget.placeholder ?? const SizedBox.shrink();
    }
    if (_error != null) {
      final err = widget.errorBuilder;
      return err == null
          ? const SizedBox.shrink()
          : err(context, _error!);
    }
    final image = _resolved;
    if (image == null) {
      final lb = widget.loadingBuilder;
      return lb == null ? const SizedBox.shrink() : lb(context);
    }
    return CustomPaint(
      size: Size(widget.width ?? frame.region.width,
          widget.height ?? frame.region.height),
      painter: _SpriteCropPainter(
        image: image,
        srcRect: frame.region,
        filterQuality: widget.filterQuality,
      ),
      child: SizedBox(width: widget.width, height: widget.height),
    );
  }
}

class _SpriteCropPainter extends CustomPainter {
  _SpriteCropPainter({
    required this.image,
    required this.srcRect,
    required this.filterQuality,
  });

  final ui.Image image;
  final Rect srcRect;
  final FilterQuality filterQuality;

  @override
  void paint(Canvas canvas, Size size) {
    final dstRect = Offset.zero & size;
    canvas.drawImageRect(
      image,
      srcRect,
      dstRect,
      Paint()..filterQuality = filterQuality,
    );
  }

  @override
  bool shouldRepaint(covariant _SpriteCropPainter old) =>
      !identical(old.image, image) ||
      old.srcRect != srcRect ||
      old.filterQuality != filterQuality;
}
