import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'player_backend.dart';

/// [PlayerError] 的粗粒度分类。app 级代码用它判断是否重试、是否给用户
/// 提示、是否切到 fallback 线路。取代以前用正则匹配错误字符串的做法。
enum PlayerErrorCategory {
  /// 播放中*可能*会自己恢复的小卡顿（单次解码 glitch、已发出若干帧
  /// 之后的短暂网络停顿）。UI 可以保留播放器，由调用方决定是否重试。
  transient,

  /// 解码器根本无法处理本流的 codec / 容器。
  /// 如果是格式问题，换解码器（例如 video_player → IJK）也救不了；
  /// 但换*线路*（转码后的另一条线路）有可能。
  codecUnsupported,

  /// 网络或 I/O 失败——DNS、TCP、TLS、HTTP、分片 404。解码器没问题，
  /// 是字节没传到。调用方应重试线路或弹"网络不好"。
  network,

  /// 永久失败、没有显而易见的恢复路径（服务端播放器挂了、关键元数据
  /// 损坏等）。不要重试。
  terminal,

  /// 无法分类——按不透明处理。对只能拿到自由格式 `errorDescription`
  /// 的 video_player 错误，默认就是这个。
  unknown,
}

/// `phase == error` 时附在 [NiumaPlayerValue] 上的结构化错误。
/// 取代以前把 `"$code/extra=$extra@${pos}ms"` 塞进单条 `errorMessage`
/// 字符串的做法；消费方现在可以直接 switch [category]，而不是去
/// 模式匹配信息文本。
@immutable
class PlayerError {
  const PlayerError({
    required this.category,
    required this.message,
    this.code,
  });

  final PlayerErrorCategory category;
  final String message;

  /// 可用时为 native 错误码（例如 IJK 的 `what` 值的字符串形式）。
  /// 仅供诊断；消费方应基于 [category] 做逻辑决策。
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

/// 互斥的播放阶段。是"当前在做什么"的唯一事实来源；其它状态
/// （`isPlaying`、`isBuffering`、`isCompleted`、`initialized`、
/// `hasError`）都由它派生。
///
/// 状态机（仅前向边）：
/// ```
///   idle → opening → ready ⇄ playing ⇄ paused
///                             ↘    ↑    ↗
///                              buffering
///   playing/paused/buffering → ended  （未 looping 时）
///   any → error
/// ```
enum PlayerPhase {
  /// [PlayerBackend.initialize] 调用之前。默认状态。
  idle,

  /// native 侧正在准备 source（解复用探测、解码器预热、首帧）。
  /// Android 上对应 `prepareAsync` 进行中；可选的 `openingStage`
  /// 标注当前在哪个子步骤。
  opening,

  /// 已准备好，但还没有播放意图。`opening` 成功后到达；首次 `play()`
  /// 后变为 `playing`。
  ready,

  /// 正在渲染帧。
  playing,

  /// 用户主动暂停。与 `buffering`（非自愿）区分。
  paused,

  /// 播放意图为真但解码器拿不到数据。UI 应保留"暂停"图标——因为用户
  /// *想*继续播——见 [NiumaPlayerValue.effectivelyPlaying]。
  buffering,

  /// 未 looping 状态下到达媒体结尾。`position == duration`。
  /// 当 `setLooping(true)` 时 native **不应**进入该状态——它应当
  /// 透明地回到 `playing`。
  ended,

  /// 终止错误。`errorMessage` 已设置。
  error,
}

/// [NiumaPlayerController] 状态的不可变快照。
///
/// 字段集围绕 [PlayerPhase] 作为唯一事实来源构造。经典布尔访问器
/// （`isPlaying`、`isBuffering`、`isCompleted`、`initialized`、
/// `hasError`）作为兼容性 getter 保留，旧契约下编写的消费方不会
/// 被破坏。
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

  /// 底层播放器已加载到 [duration] 中的多远位置。驱动进度条上的
  /// "已缓冲段"灰条。
  final Duration bufferedPosition;

  /// `phase == opening` 时的可选子阶段描述（例如 `"openInput"`、
  /// `"findStreamInfo"`、`"componentOpen"`）。会被填到 timeout /
  /// 错误信息里用作诊断。否则为 null。
  final String? openingStage;

  /// 结构化错误信息；仅当 `phase == error` 时非 null。用
  /// [PlayerError.category] 驱动重试 / 回退 / UI 决策。
  final PlayerError? error;

  // ────────────── 兼容性 getter（由 phase 派生） ──────────────

  /// 纯文本错误描述，给在 [PlayerError] 出现前写的调用方保留。
  String? get errorMessage => error?.message;

  /// backend 拿到 metadata 并准备好播放（或更进一步）后为 true。
  /// 取代旧的显式 `initialized` 字段——现在 value 是 [phase] 的函数，
  /// 不可能与快照其它字段不一致。
  bool get initialized =>
      phase != PlayerPhase.idle && phase != PlayerPhase.opening;

  bool get isPlaying => phase == PlayerPhase.playing;
  bool get isBuffering => phase == PlayerPhase.buffering;

  /// 是否未 looping 自然播完。native 应在内部处理 looping——
  /// `setLooping(true)` 时本字段绝不应变为 true。
  bool get isCompleted => phase == PlayerPhase.ended;

  bool get hasError => phase == PlayerPhase.error;

  /// 面向用户的"播放按钮是否应该隐藏"——只要用户*想要*播放（即使
  /// 解码器暂时缺数据）即为 true。用以取代消费方过去必须保留的
  /// `_intentPlaying && !isCompleted` 兜底逻辑（避免 buffering 期间的
  /// 闪烁）。
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
  }) {
    return NiumaPlayerValue(
      phase: phase ?? this.phase,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      openingStage: clearOpeningStage
          ? null
          : (openingStage ?? this.openingStage),
      error: clearError ? null : (error ?? this.error),
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
        other.error == error;
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
        'error: $error)';
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

  /// 当本次选择来自 [DeviceMemory] 而非实时尝试时为 true。
  final bool fromMemory;

  @override
  String toString() =>
      'BackendSelected(kind: $kind, fromMemory: $fromMemory)';
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

  /// 可用时为底层 [PlayerError] 的分类。让下游选择逻辑把"解码器读不
  /// 出"（值得回退到 IJK）和"网络断了"（没意义）区分开。
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
