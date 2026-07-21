import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'package:niuma_player/src/cast/cast_device.dart';
import 'package:niuma_player/src/cast/cast_state.dart';
import 'package:niuma_player/src/domain/player_backend.dart';

/// [PlayerError] 的粗粒度分类，供上层判断是否重试 / 提示 / 切线路。
enum PlayerErrorCategory {
  /// 可能自愈的小卡顿，调用方自行决定是否重试。
  transient,

  /// 解码器无法处理本流的 codec / 容器——换解码器救不了，换线路有可能。
  codecUnsupported,

  /// 网络 / I/O 失败（DNS、TCP、HTTP、分片 404），应重试线路或提示。
  network,

  /// 永久失败，无恢复路径，不要重试。
  terminal,

  /// 无法分类——video_player 只有自由格式 errorDescription 时默认这个。
  unknown,
}

/// `phase == error` 时附在 [NiumaPlayerValue] 上的结构化错误，
/// 消费方直接 switch [category]，不必模式匹配信息文本。
@immutable
/// Android 上 ExoPlayer 与 IJK 兜底**双双失败**时抛出的组合异常。
/// 同时携带两段错误——只报 IJK 的会掩盖 ExoPlayer 的根因（如 HTTP 403）。
class EngineFallbackFailure implements Exception {
  /// 构造组合异常。
  const EngineFallbackFailure({required this.primary, required this.fallback});

  /// ExoPlayer（主内核）的原始错误。
  final Object primary;

  /// IJK（兜底内核）重试后的错误。
  final Object fallback;

  @override
  String toString() =>
      '两个内核均失败 — ExoPlayer: $primary ; IJK fallback: $fallback';
}

class PlayerError {
  const PlayerError({
    required this.category,
    required this.message,
    this.code,
  });

  final PlayerErrorCategory category;
  final String message;

  /// native 错误码（如 IJK 的 `what`），仅供诊断；决策请基于 [category]。
  final String? code;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlayerError &&
        other.category == category &&
        other.message == message &&
        other.code == code;
  }

  @override
  int get hashCode => Object.hash(category, message, code);

  @override
  String toString() =>
      'PlayerError(category: $category, code: $code, message: $message)';
}

/// 互斥的播放阶段——"当前在做什么"的唯一事实来源，`isPlaying` 等
/// 布尔状态全部由它派生。
enum PlayerPhase {
  /// [PlayerBackend.initialize] 之前的默认状态。
  idle,

  /// native 侧正在准备 source；`openingStage` 标注子步骤。
  opening,

  /// 已准备好但还没有播放意图，首次 `play()` 后变 `playing`。
  ready,

  /// 正在渲染帧。
  playing,

  /// 用户主动暂停，与 `buffering`（非自愿）区分。
  paused,

  /// 播放意图为真但解码器拿不到数据，见
  /// [NiumaPlayerValue.effectivelyPlaying]。
  buffering,

  /// 未 looping 时到达媒体结尾；looping 时 native 不应进入该状态。
  ended,

  /// 终止错误，`errorMessage` 已设置。
  error,
}

/// [NiumaPlayerController] 状态的不可变快照，以 [PlayerPhase] 为唯一
/// 事实来源；经典布尔 getter 作兼容保留。
@immutable
class NiumaPlayerValue {
  const NiumaPlayerValue({
    required this.phase,
    required this.position,
    required this.duration,
    required this.size,
    required this.bufferedPosition,
    this.openingStage,
    this.error,
    this.playbackSpeed = 1.0,
    this.isInPictureInPicture = false,
    this.isPictureInPictureSupported = false,
  });

  /// 空初始值（[PlayerBackend.initialize] 之前）。
  factory NiumaPlayerValue.uninitialized() => const NiumaPlayerValue(
        phase: PlayerPhase.idle,
        position: Duration.zero,
        duration: Duration.zero,
        size: Size.zero,
        bufferedPosition: Duration.zero,
      );

  final PlayerPhase phase;
  final Duration position;
  final Duration duration;
  final Size size;

  /// 已缓冲到的位置，驱动进度条"已缓冲段"灰条。
  final Duration bufferedPosition;

  /// `phase == opening` 时的子阶段描述（如 `"openInput"`），供诊断。
  final String? openingStage;

  /// 结构化错误，仅 `phase == error` 时非 null。
  final PlayerError? error;

  /// 当前倍速（默认 1.0）。由 [NiumaPlayerController.setPlaybackSpeed] 更新。
  final double playbackSpeed;

  /// 当前是否在 PiP 小窗模式中，由原生侧推送状态变化。
  final bool isInPictureInPicture;

  /// 设备 + 当前视频是否支持 PiP（iOS 15+ / Android 8.0+，且已 initialize）。
  /// initialize 前为 false。
  final bool isPictureInPictureSupported;

  // ────────────── 兼容性 getter（由 phase 派生） ──────────────

  /// 纯文本错误描述（兼容 getter）。
  String? get errorMessage => error?.message;

  /// backend 拿到 metadata 并可播后为 true，由 [phase] 派生。
  bool get initialized =>
      phase != PlayerPhase.idle && phase != PlayerPhase.opening;

  bool get isPlaying => phase == PlayerPhase.playing;
  bool get isBuffering => phase == PlayerPhase.buffering;

  /// 是否未 looping 自然播完；looping 时绝不为 true。
  bool get isCompleted => phase == PlayerPhase.ended;

  bool get hasError => phase == PlayerPhase.error;

  /// 用户*想要*播放即为 true（含 buffering），避免缓冲期间播放按钮闪烁。
  bool get effectivelyPlaying =>
      phase == PlayerPhase.playing || phase == PlayerPhase.buffering;

  double get aspectRatio {
    if (!initialized || size.width == 0 || size.height == 0) {
      return 1.0;
    }
    return size.width / size.height;
  }

  NiumaPlayerValue copyWith({
    PlayerPhase? phase,
    Duration? position,
    Duration? duration,
    Size? size,
    Duration? bufferedPosition,
    String? openingStage,
    bool clearOpeningStage = false,
    // 用一个 sentinel 显式置 null：传 `clearError: true` 来重置。
    PlayerError? error,
    bool clearError = false,
    double? playbackSpeed,
    bool? isInPictureInPicture,
    bool? isPictureInPictureSupported,
  }) {
    return NiumaPlayerValue(
      phase: phase ?? this.phase,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      openingStage:
          clearOpeningStage ? null : (openingStage ?? this.openingStage),
      error: clearError ? null : (error ?? this.error),
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      isInPictureInPicture: isInPictureInPicture ?? this.isInPictureInPicture,
      isPictureInPictureSupported:
          isPictureInPictureSupported ?? this.isPictureInPictureSupported,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NiumaPlayerValue &&
        other.phase == phase &&
        other.position == position &&
        other.duration == duration &&
        other.size == size &&
        other.bufferedPosition == bufferedPosition &&
        other.openingStage == openingStage &&
        other.error == error &&
        other.playbackSpeed == playbackSpeed &&
        other.isInPictureInPicture == isInPictureInPicture &&
        other.isPictureInPictureSupported == isPictureInPictureSupported;
  }

  @override
  int get hashCode => Object.hash(
        phase,
        position,
        duration,
        size,
        bufferedPosition,
        openingStage,
        error,
        playbackSpeed,
        isInPictureInPicture,
        isPictureInPictureSupported,
      );

  @override
  String toString() {
    return 'NiumaPlayerValue('
        'phase: $phase, '
        'position: $position, '
        'duration: $duration, '
        'size: $size, '
        'bufferedPosition: $bufferedPosition, '
        'openingStage: $openingStage, '
        'error: $error, '
        'playbackSpeed: $playbackSpeed, '
        'isInPictureInPicture: $isInPictureInPicture, '
        'isPictureInPictureSupported: $isPictureInPictureSupported)';
  }
}

/// controller 从 video_player 回退到 IJK 的原因。
enum FallbackReason { error, timeout }

/// 在 [NiumaPlayerController.events] 上发出的事件，让 app 记录或响应
/// backend 选择 / 回退行为。
sealed class NiumaPlayerEvent {
  const NiumaPlayerEvent();
}

/// 每次 [NiumaPlayerController.initialize] 成功后精确触发一次，告知最终
/// 选中的 backend。
final class BackendSelected extends NiumaPlayerEvent {
  const BackendSelected(this.kind, {required this.fromMemory});

  final PlayerBackendKind kind;

  /// 【已废弃语义】设备记忆已移除，恒为 `false`；仅为兼容保留，
  /// 后续 major 版本删除。
  final bool fromMemory;

  @override
  String toString() => 'BackendSelected(kind: $kind, fromMemory: $fromMemory)';
}

/// controller 因错误或 timeout 不得不拆掉 video_player 启动 IJK 时
/// 触发。
final class FallbackTriggered extends NiumaPlayerEvent {
  const FallbackTriggered(
    this.reason, {
    this.errorCode,
    this.errorCategory,
  });

  final FallbackReason reason;
  final String? errorCode;

  /// 底层 [PlayerError] 分类——区分"解码失败"（值得回退 IJK）和
  /// "网络断了"（回退没意义）。
  final PlayerErrorCategory? errorCategory;

  @override
  String toString() =>
      'FallbackTriggered(reason: $reason, errorCode: $errorCode, '
      'errorCategory: $errorCategory)';
}

/// [NiumaPlayerController.switchLine] 开始拆掉当前 backend、准备拉起
/// 新线路时触发。
final class LineSwitching extends NiumaPlayerEvent {
  const LineSwitching({required this.fromId, required this.toId});

  /// 之前激活的线路 id。
  final String fromId;

  /// controller 正在切向的线路 id。
  final String toId;

  @override
  String toString() => 'LineSwitching(from: $fromId, to: $toId)';
}

/// [NiumaPlayerController.switchLine] 成功在目标线路上拉起新 backend
/// 后精确触发一次。
final class LineSwitched extends NiumaPlayerEvent {
  const LineSwitched(this.toId);

  /// 当前激活的线路 id。
  final String toId;

  @override
  String toString() => 'LineSwitched(to: $toId)';
}

/// [NiumaPlayerController.switchLine] 无法拉起新线路时触发。当前
/// backend（如果有）保持原状；调用方自行决定是否手动尝试其它线路。
final class LineSwitchFailed extends NiumaPlayerEvent {
  const LineSwitchFailed({required this.toId, required this.error});

  /// controller 切换失败的目标线路 id。
  final String toId;

  /// 来自 backend 或 middleware 流水线的底层错误。
  final Object error;

  @override
  String toString() => 'LineSwitchFailed(to: $toId, error: $error)';
}

/// PiP 模式状态变化事件，原生侧推送。
final class PipModeChanged extends NiumaPlayerEvent {
  /// 构造一个事件。
  const PipModeChanged({required this.isInPip});

  /// 进入 PiP 时为 true，退出时为 false。
  final bool isInPip;
}

/// PiP 窗内 RemoteAction 触发事件（Android only——iOS stock 控件由
/// AVPlayer 自己处理，不走此事件）。
final class PipRemoteAction extends NiumaPlayerEvent {
  /// 构造一个事件。
  const PipRemoteAction({required this.action});

  /// 动作类型：当前仅 `'playPauseToggle'`。后续可能加 prev/next 等。
  final String action;
}

/// 投屏开始。
final class CastStarted extends NiumaPlayerEvent {
  const CastStarted(this.device);
  final CastDevice device;
}

/// 投屏结束。
final class CastEnded extends NiumaPlayerEvent {
  const CastEnded(this.reason);
  final CastEndReason reason;
}

/// 投屏出错（与 CastEnded 区别：可恢复 / 不可恢复看 reason）。
final class CastError extends NiumaPlayerEvent {
  const CastError({required this.code, this.message});
  final String code;
  final String? message;
}
