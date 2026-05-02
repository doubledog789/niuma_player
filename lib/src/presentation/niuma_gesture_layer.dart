import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/gesture_feedback_state.dart';
import '../domain/gesture_kind.dart';
import '../domain/player_state.dart';
import 'niuma_gesture_hud.dart';
import 'niuma_player_controller.dart';
import 'video_time_format.dart';

/// HUD 自定义 builder 类型。
typedef GestureHudBuilder = Widget Function(
  BuildContext context,
  GestureFeedbackState state,
);

/// 视频手势层——5 项核心手势 + HUD 协调。
///
/// 默认仅在全屏页生效（通过 [enabled] 字段控制）；inline 场景由
/// `NiumaPlayer.gesturesEnabledInline` 决定 enabled。
///
/// 5 项手势：
/// - 双击 → controller.play/pause
/// - 长按 → 临时 2x，松手恢复
/// - 水平 pan → seek（松手才提交）
/// - 左半屏垂直 pan → 亮度（立即生效，节流 50ms）
/// - 右半屏垂直 pan → 音量（同上）
class NiumaGestureLayer extends StatefulWidget {
  /// 构造一个 gesture layer。
  const NiumaGestureLayer({
    super.key,
    required this.controller,
    this.disabledGestures = const {},
    this.hudBuilder,
    this.onTap,
    this.enabled = true,
    required this.child,
  });

  /// 被驱动的 controller。
  final NiumaPlayerController controller;

  /// 黑名单：不触发的手势类型。
  final Set<GestureKind> disabledGestures;

  /// HUD 自定义 builder。null = 用 [NiumaGestureHud] 默认。
  final GestureHudBuilder? hudBuilder;

  /// onTap 透传——M9 既有的"单击切控件显隐"通过这个保留行为。
  final VoidCallback? onTap;

  /// 整体是否启用。false = 仅透传 onTap，其他手势全部跳过。
  final bool enabled;

  /// 内层视频 view（NiumaPlayerView 等）。
  final Widget child;

  @override
  State<NiumaGestureLayer> createState() => _NiumaGestureLayerState();
}

class _NiumaGestureLayerState extends State<NiumaGestureLayer> {
  GestureKind? _lockedKind;
  Offset _panStart = Offset.zero;
  Duration _seekStart = Duration.zero;
  double _origValue = 0.0;
  double? _originalSpeed;
  Timer? _hideTimer;
  double? _initialBrightness;
  DateTime? _lastChannelSet;

  static const double _dragThreshold = 18;

  bool _isDisabled(GestureKind kind) =>
      widget.disabledGestures.contains(kind);

  @override
  void initState() {
    super.initState();
    // 异步读初始亮度，dispose 时恢复
    widget.controller.backend?.getBrightness().then((v) {
      if (mounted) _initialBrightness = v;
    });
  }

  void _showHud(GestureFeedbackState state) {
    widget.controller.setGestureFeedbackInternal(state);
    _hideTimer?.cancel();
  }

  void _scheduleHide() {
    _hideTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        widget.controller.setGestureFeedbackInternal(null);
      }
    });
  }

  void _onTap() {
    widget.onTap?.call();
  }

  void _onDoubleTap() {
    if (_isDisabled(GestureKind.doubleTap)) return;
    final phase = widget.controller.value.phase;
    if (phase == PlayerPhase.playing) {
      widget.controller.pause();
      _showHud(const GestureFeedbackState(
        kind: GestureKind.doubleTap,
        progress: 1.0,
        label: '已暂停',
        icon: Icons.pause,
      ));
    } else {
      widget.controller.play();
      _showHud(const GestureFeedbackState(
        kind: GestureKind.doubleTap,
        progress: 1.0,
        label: '播放中',
        icon: Icons.play_arrow,
      ));
    }
    _scheduleHide();
  }

  void _onLongPressStart(LongPressStartDetails _) {
    if (_isDisabled(GestureKind.longPressSpeed)) return;
    _originalSpeed = widget.controller.value.playbackSpeed;
    widget.controller.setPlaybackSpeed(2.0);
    _showHud(const GestureFeedbackState(
      kind: GestureKind.longPressSpeed,
      progress: 1.0,
      label: '2x 倍速',
      icon: Icons.fast_forward,
    ));
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    final speed = _originalSpeed;
    if (speed != null) {
      widget.controller.setPlaybackSpeed(speed);
    }
    _originalSpeed = null;
    _scheduleHide();
  }

  void _onPanStart(DragStartDetails details) {
    _panStart = details.localPosition;
    _seekStart = widget.controller.value.position;
    _lockedKind = null;
    _origValue = 0.0;
  }

  Future<void> _ensureOrigValue(GestureKind kind) async {
    final backend = widget.controller.backend;
    if (backend == null) return;
    if (kind == GestureKind.brightness) {
      _origValue = await backend.getBrightness();
    } else if (kind == GestureKind.volume) {
      _origValue = await backend.getSystemVolume();
    }
  }

  Future<void> _onPanUpdate(DragUpdateDetails details) async {
    final size = context.size;
    if (size == null) return;

    final dx = details.localPosition.dx - _panStart.dx;
    final dy = details.localPosition.dy - _panStart.dy;

    if (_lockedKind == null) {
      if (dx.abs() < _dragThreshold && dy.abs() < _dragThreshold) return;
      if (dx.abs() > dy.abs()) {
        _lockedKind = GestureKind.horizontalSeek;
      } else {
        final isLeftHalf = _panStart.dx < size.width / 2;
        _lockedKind = isLeftHalf ? GestureKind.brightness : GestureKind.volume;
      }
      if (_isDisabled(_lockedKind!)) {
        _lockedKind = null;
        return;
      }
      await _ensureOrigValue(_lockedKind!);
    }

    switch (_lockedKind!) {
      case GestureKind.horizontalSeek:
        final duration = widget.controller.value.duration;
        if (duration == Duration.zero) return;
        final seekDeltaMs =
            (dx / size.width * duration.inMilliseconds * 0.5).round();
        final target = _seekStart + Duration(milliseconds: seekDeltaMs);
        final clamped = Duration(
          milliseconds:
              target.inMilliseconds.clamp(0, duration.inMilliseconds),
        );
        _showHud(GestureFeedbackState(
          kind: GestureKind.horizontalSeek,
          progress:
              clamped.inMilliseconds / duration.inMilliseconds.clamp(1, 1 << 30),
          label: '${seekDeltaMs >= 0 ? '+' : ''}${seekDeltaMs ~/ 1000}s '
              '/ ${formatVideoTime(clamped)} / ${formatVideoTime(duration)}',
          icon: Icons.fast_forward,
        ));
      case GestureKind.brightness:
      case GestureKind.volume:
        final newValue =
            (_origValue - (dy / (size.height * 0.5))).clamp(0.0, 1.0);
        // 节流 50ms
        final now = DateTime.now();
        final canSet = _lastChannelSet == null ||
            now.difference(_lastChannelSet!) >=
                const Duration(milliseconds: 50);
        if (canSet) {
          _lastChannelSet = now;
          final backend = widget.controller.backend;
          if (backend != null) {
            if (_lockedKind == GestureKind.brightness) {
              unawaited(backend.setBrightness(newValue));
            } else {
              unawaited(backend.setSystemVolume(newValue));
            }
          }
        }
        _showHud(GestureFeedbackState(
          kind: _lockedKind!,
          progress: newValue,
          label: '${(newValue * 100).round()}%',
          icon: _lockedKind == GestureKind.brightness
              ? Icons.brightness_6
              : Icons.volume_up,
        ));
      case GestureKind.doubleTap:
      case GestureKind.longPressSpeed:
        // pan 不会进这两个 case，吞掉避免 lint
        break;
    }
  }

  void _onPanEnd(DragEndDetails _) {
    if (_lockedKind == GestureKind.horizontalSeek) {
      final hud = widget.controller.gestureFeedback.value;
      if (hud != null) {
        final duration = widget.controller.value.duration;
        final progress = hud.progress;
        final target = Duration(
          milliseconds: (duration.inMilliseconds * progress).round(),
        );
        widget.controller.seekTo(target);
      }
    }
    _lockedKind = null;
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    final orig = _initialBrightness;
    if (orig != null) {
      // 退出时恢复亮度，fire-and-forget（dispose 不能 async）
      widget.controller.backend?.setBrightness(orig);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            onDoubleTap: (widget.enabled && !_isDisabled(GestureKind.doubleTap))
              ? _onDoubleTap
              : null,
            onLongPressStart:
                widget.enabled ? _onLongPressStart : null,
            onLongPressEnd: widget.enabled ? _onLongPressEnd : null,
            onPanStart: widget.enabled ? _onPanStart : null,
            onPanUpdate: widget.enabled ? _onPanUpdate : null,
            onPanEnd: widget.enabled ? _onPanEnd : null,
            child: widget.child,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<GestureFeedbackState?>(
              valueListenable: widget.controller.gestureFeedback,
              builder: (ctx, state, _) {
                if (state == null) return const SizedBox.shrink();
                return Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: widget.hudBuilder != null
                        ? KeyedSubtree(
                            key: ValueKey(state.kind),
                            child: widget.hudBuilder!(ctx, state),
                          )
                        : NiumaGestureHud(
                            key: ValueKey(state.kind),
                            state: state,
                          ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
