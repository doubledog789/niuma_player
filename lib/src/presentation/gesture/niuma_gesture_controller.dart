import 'dart:async';
import 'dart:ui' show Offset, Size;

import 'package:niuma_player/src/domain/gesture_feedback_state.dart';
import 'package:niuma_player/src/domain/gesture_kind.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/niuma_sdk_assets.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_controller.dart';
import 'package:niuma_player/src/presentation/shared/video_time_format.dart';

/// 视频手势的 **headless 编排器**——把"原始手势几何量 → 播放意图 + HUD 反馈"
/// 的纯逻辑从 widget 里剥出来，不持有任何 `BuildContext` / widget tree 概念。
///
/// widget（参考皮里的 gesture layer）只负责：用 `GestureDetector` 把
/// double-tap / long-press / pan 的本地坐标 + 容器尺寸透传给本类的对应方法；
/// HUD 的渲染则监听 [NiumaPlayerController.gestureFeedback]。
///
/// 5 项手势（与原 `NiumaGestureLayer` 行为一致）：
/// - 双击 → play / pause
/// - 长按 → 临时 2x 倍速，松手恢复
/// - 水平 pan → seek（松手才提交）
/// - 左半屏垂直 pan → 亮度（立即生效，节流 50ms）
/// - 右半屏垂直 pan → 音量（同上）
///
/// HUD 反馈只产出 [GestureFeedbackState.iconAsset]（SDK 资源路径），不引
/// material `Icons`——5 项手势的 HUD 资源包都已覆盖，所以核里零 material 依赖；
/// 参考皮的 HUD widget 按 iconAsset 渲染即可。
class NiumaGestureController {
  /// 构造一个手势编排器，驱动给定 [player]。
  NiumaGestureController(this.player, {this.disabledGestures = const {}});

  /// 被驱动的 controller。
  final NiumaPlayerController player;

  /// 黑名单：不触发的手势类型。
  final Set<GestureKind> disabledGestures;

  GestureKind? _lockedKind;
  Offset _panStart = Offset.zero;
  Duration _seekStart = Duration.zero;
  double _origValue = 0.0;
  double? _originalSpeed;
  Timer? _hideTimer;
  double? _initialBrightness;
  DateTime? _lastChannelSet;

  static const double _dragThreshold = 18;

  bool _isDisabled(GestureKind kind) => disabledGestures.contains(kind);

  /// 异步读初始亮度，[restoreBrightness] 时恢复。widget 在 init 时调一次。
  void initBrightness() {
    player.backend?.getBrightness().then((v) {
      _initialBrightness = v;
    });
  }

  void _showHud(GestureFeedbackState state) {
    player.setGestureFeedbackInternal(state);
    _hideTimer?.cancel();
  }

  void _scheduleHide() {
    _hideTimer = Timer(const Duration(milliseconds: 600), () {
      player.setGestureFeedbackInternal(null);
    });
  }

  /// 双击 → 切播放 / 暂停。
  void onDoubleTap() {
    if (_isDisabled(GestureKind.doubleTap)) return;
    final phase = player.value.phase;
    if (phase == PlayerPhase.playing) {
      player.pause();
      _showHud(const GestureFeedbackState(
        kind: GestureKind.doubleTap,
        progress: 1.0,
        label: '已暂停',
        iconAsset: NiumaSdkAssets.icPause,
      ));
    } else {
      player.play();
      _showHud(const GestureFeedbackState(
        kind: GestureKind.doubleTap,
        progress: 1.0,
        label: '播放中',
        iconAsset: NiumaSdkAssets.icPlay,
      ));
    }
    _scheduleHide();
  }

  /// 长按开始 → 临时 2x 倍速。
  void onLongPressStart() {
    if (_isDisabled(GestureKind.longPressSpeed)) return;
    _originalSpeed = player.value.playbackSpeed;
    player.setPlaybackSpeed(2.0);
    _showHud(const GestureFeedbackState(
      kind: GestureKind.longPressSpeed,
      progress: 1.0,
      label: '2x 倍速',
      iconAsset: NiumaSdkAssets.icSpeedAlt,
    ));
  }

  /// 长按结束 → 恢复原倍速。
  void onLongPressEnd() {
    final speed = _originalSpeed;
    if (speed != null) {
      player.setPlaybackSpeed(speed);
    }
    _originalSpeed = null;
    _scheduleHide();
  }

  /// pan 开始 → 记录起点，清锁定方向。[localPosition] 为手势相对视频区的坐标。
  void onPanStart(Offset localPosition) {
    _panStart = localPosition;
    _seekStart = player.value.position;
    _lockedKind = null;
    _origValue = 0.0;
  }

  Future<void> _ensureOrigValue(GestureKind kind) async {
    final backend = player.backend;
    if (backend == null) return;
    if (kind == GestureKind.brightness) {
      _origValue = await backend.getBrightness();
    } else if (kind == GestureKind.volume) {
      _origValue = await backend.getSystemVolume();
    }
  }

  /// pan 更新 → 首次过阈值时锁定方向（水平 seek / 左亮度 / 右音量），之后按锁定
  /// 方向更新。[size] 为视频区尺寸（用于左右半屏判定与位移归一）。
  Future<void> onPanUpdate(Offset localPosition, Size size) async {
    final dx = localPosition.dx - _panStart.dx;
    final dy = localPosition.dy - _panStart.dy;

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
        final duration = player.value.duration;
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
          iconAsset: seekDeltaMs >= 0
              ? NiumaSdkAssets.icForward10
              : NiumaSdkAssets.icRewind10,
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
          final backend = player.backend;
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
          // 资源包约定：ic_settings 是亮度图标；ic_volume / ic_volume_mute
          // 是音量图标（音量为 0 走 mute 版本）。
          iconAsset: _lockedKind == GestureKind.brightness
              ? NiumaSdkAssets.icSettings
              : (newValue == 0
                  ? NiumaSdkAssets.icVolumeMute
                  : NiumaSdkAssets.icVolume),
        ));
      case GestureKind.doubleTap:
      case GestureKind.longPressSpeed:
        // pan 不会进这两个 case，吞掉避免 lint
        break;
    }
  }

  /// pan 结束 → 水平 seek 时按当前 HUD 进度提交 seek。
  void onPanEnd() {
    if (_lockedKind == GestureKind.horizontalSeek) {
      final hud = player.gestureFeedback.value;
      if (hud != null) {
        final duration = player.value.duration;
        final progress = hud.progress;
        final target = Duration(
          milliseconds: (duration.inMilliseconds * progress).round(),
        );
        player.seekTo(target);
      }
    }
    _lockedKind = null;
    _scheduleHide();
  }

  /// 释放：停 HUD 计时器，并把亮度恢复到 [initBrightness] 读到的初值。
  void dispose() {
    _hideTimer?.cancel();
    restoreBrightness();
  }

  /// 把屏幕亮度恢复到进入手势区前的初值（fire-and-forget）。
  void restoreBrightness() {
    final orig = _initialBrightness;
    if (orig != null) {
      player.backend?.setBrightness(orig);
    }
  }
}
