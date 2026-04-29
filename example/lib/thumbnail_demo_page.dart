import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:niuma_player/niuma_player.dart';

import 'samples.dart';

/// M8 demo: 进度条拖动时显示 sprite 缩略图预览。
class ThumbnailDemoPage extends StatefulWidget {
  const ThumbnailDemoPage({super.key, required this.sample});

  final ThumbnailVttSample sample;

  @override
  State<ThumbnailDemoPage> createState() => _ThumbnailDemoPageState();
}

class _ThumbnailDemoPageState extends State<ThumbnailDemoPage> {
  late final NiumaPlayerController _controller;
  StreamSubscription<NiumaPlayerEvent>? _eventsSub;

  /// While the user is dragging the scrubber, the in-flight value (in ms).
  /// Drives the thumbnail preview position; null when not dragging.
  double? _scrubMs;

  /// Last frame returned from controller.thumbnailFor(...). Cached so a single
  /// build can paint without async re-lookup.
  ThumbnailFrame? _previewFrame;

  @override
  void initState() {
    super.initState();
    _controller = NiumaPlayerController.dataSource(
      NiumaDataSource.network(widget.sample.videoUrl),
      thumbnailVtt: widget.sample.thumbnailVttUrl,
    );
    _eventsSub = _controller.events.listen((_) => _safeSetState(() {}));
    _controller.addListener(_onValueChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      await _controller.play();
    } catch (e) {
      debugPrint('initialize() threw: $e');
    }
  }

  void _onValueChanged() => _safeSetState(() {});

  /// setState 的防御版：如果当前正在 build/layout/paint（scheduler 把 widget tree
  /// 锁了），直接调 setState 会抛 "framework is locked"。M7 的 events stream
  /// 是 sync 的，ValueNotifier 的 listener 也是同步触发，二者都可能在 build
  /// 中段 fire。这里检测一下 phase，需要时延后到下一帧。
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      // 在 build / layout / paint 阶段，延后。
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onValueChanged);
    unawaited(_eventsSub?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  Duration _scrubPosition() {
    final ms = _scrubMs ??
        _controller.value.position.inMilliseconds.toDouble();
    return Duration(milliseconds: ms.toInt());
  }

  @override
  Widget build(BuildContext context) {
    final v = _controller.value;
    final durMs = v.duration.inMilliseconds.toDouble();
    final hasDuration = durMs > 0;
    _previewFrame = _controller.thumbnailFor(_scrubPosition());

    return Scaffold(
      appBar: AppBar(title: Text(widget.sample.label)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: <Widget>[
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: !v.initialized
                  ? const Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                    )
                  : NiumaPlayerView(_controller),
            ),
          ),
          const SizedBox(height: 16),
          _scrubberWithPreview(hasDuration: hasDuration, durMs: durMs),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              IconButton(
                icon: Icon(
                  v.effectivelyPlaying ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: !v.initialized
                    ? null
                    : () => v.effectivelyPlaying
                        ? _controller.pause()
                        : _controller.play(),
              ),
              const SizedBox(width: 12),
              Text(
                '${_fmt(_scrubPosition())} / '
                '${hasDuration ? _fmt(v.duration) : "--:--"}',
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              Text(
                _previewFrame == null
                    ? 'thumbnail: 未加载'
                    : 'thumbnail: ${_previewFrame!.region.width.toInt()}×${_previewFrame!.region.height.toInt()}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _explainer(),
        ],
      ),
    );
  }

  /// Custom scrubber with thumbnail preview floating above the touch point.
  ///
  /// Uses [GestureDetector] instead of [Slider] for two reasons:
  ///   1. Slider's hit zone is tight — hard to enter drag without immediately
  ///      committing a seek.
  ///   2. We want the preview to appear on press-down (before the user
  ///      decides whether to release or drag), then commit seek on release.
  Widget _scrubberWithPreview({required bool hasDuration, required double durMs}) {
    final v = _controller.value;
    final displayMs = _scrubMs ?? v.position.inMilliseconds.toDouble();
    final bufMs = v.bufferedPosition.inMilliseconds.toDouble();

    return SizedBox(
      height: 140,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final progress = hasDuration ? (displayMs / durMs).clamp(0.0, 1.0) : 0.0;
          final thumbX = width * progress;
          // Preview is 160 wide; clamp so it stays in screen.
          final previewLeft = (thumbX - 80).clamp(0.0, width - 160);

          double xToMs(double x) {
            final clamped = x.clamp(0.0, width);
            return hasDuration ? (clamped / width) * durMs : 0;
          }

          Future<void> commitSeek() async {
            final ms = _scrubMs;
            if (ms != null) {
              await _controller.seekTo(Duration(milliseconds: ms.toInt()));
            }
            _safeSetState(() => _scrubMs = null);
          }

          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // Thumbnail preview (only while user is touching the bar)
              if (_scrubMs != null)
                Positioned(
                  left: previewLeft.toDouble(),
                  top: 0,
                  child: Container(
                    width: 160,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: Colors.white70, width: 1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: NiumaThumbnailView(
                      frame: _previewFrame,
                      width: 160,
                      height: 90,
                      loadingBuilder: (_) => const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // The custom progress bar — Listener (raw pointer events) gives
              // immediate touch-to-drag without the GestureDetector arena's
              // tap/drag arbitration delay.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 40,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: hasDuration
                      ? (e) => _safeSetState(
                            () => _scrubMs = xToMs(e.localPosition.dx),
                          )
                      : null,
                  onPointerMove: hasDuration
                      ? (e) => _safeSetState(
                            () => _scrubMs = xToMs(e.localPosition.dx),
                          )
                      : null,
                  onPointerUp: hasDuration ? (_) => commitSeek() : null,
                  onPointerCancel: hasDuration
                      ? (_) => _safeSetState(() => _scrubMs = null)
                      : null,
                  child: CustomPaint(
                    painter: _ScrubBarPainter(
                      progress: progress,
                      bufferedProgress:
                          hasDuration ? (bufMs / durMs).clamp(0.0, 1.0) : 0.0,
                      activeColor: Theme.of(context).colorScheme.primary,
                      thumbColor: Theme.of(context).colorScheme.primary,
                      isDragging: _scrubMs != null,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _explainer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '验证内容',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          SizedBox(height: 6),
          Text(
            '1. VTT 文件应在视频开始播放后异步加载（playing 几秒后再拖动会有缩略图）。',
            style: TextStyle(fontSize: 12),
          ),
          SizedBox(height: 4),
          Text(
            '2. 拖动进度条时，thumb 上方应出现 sprite 截图，跟随手指移动。',
            style: TextStyle(fontSize: 12),
          ),
          SizedBox(height: 4),
          Text(
            '3. 松开手指后预览消失，视频跳到对应位置。',
            style: TextStyle(fontSize: 12),
          ),
          SizedBox(height: 4),
          Text(
            '4. 若 VTT 加载失败（网络问题），右下"thumbnail: 未加载"会一直显示，'
            '但视频本身完全不受影响（M8 静默降级承诺）。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }
}

/// Custom progress bar painter: track + buffered fill + active fill + thumb.
/// Thumb grows when [isDragging] so the user gets visual feedback that the
/// scrubber has engaged.
class _ScrubBarPainter extends CustomPainter {
  _ScrubBarPainter({
    required this.progress,
    required this.bufferedProgress,
    required this.activeColor,
    required this.thumbColor,
    required this.isDragging,
  });

  final double progress;
  final double bufferedProgress;
  final Color activeColor;
  final Color thumbColor;
  final bool isDragging;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const trackHeight = 4.0;
    final trackTop = centerY - trackHeight / 2;
    final trackRect = RRect.fromLTRBR(
      0,
      trackTop,
      size.width,
      trackTop + trackHeight,
      const Radius.circular(2),
    );

    // Background track
    canvas.drawRRect(
      trackRect,
      Paint()..color = Colors.grey.withValues(alpha: 0.3),
    );

    // Buffered fill
    if (bufferedProgress > 0) {
      final bufRect = RRect.fromLTRBR(
        0,
        trackTop,
        size.width * bufferedProgress,
        trackTop + trackHeight,
        const Radius.circular(2),
      );
      canvas.drawRRect(
        bufRect,
        Paint()..color = Colors.grey.withValues(alpha: 0.55),
      );
    }

    // Active fill
    if (progress > 0) {
      final activeRect = RRect.fromLTRBR(
        0,
        trackTop,
        size.width * progress,
        trackTop + trackHeight,
        const Radius.circular(2),
      );
      canvas.drawRRect(activeRect, Paint()..color = activeColor);
    }

    // Thumb
    final thumbX = size.width * progress;
    final thumbRadius = isDragging ? 9.0 : 6.0;
    canvas.drawCircle(
      Offset(thumbX, centerY),
      thumbRadius,
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(covariant _ScrubBarPainter old) =>
      old.progress != progress ||
      old.bufferedProgress != bufferedProgress ||
      old.activeColor != activeColor ||
      old.isDragging != isDragging;
}

