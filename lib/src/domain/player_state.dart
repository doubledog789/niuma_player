import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'player_backend.dart';

/// Coarse classification of [PlayerError]s. Used by app-level code to decide
/// whether to retry, surface a user-visible message, or switch to a fallback
/// source line. Replaces the old practice of regex-matching error strings.
enum PlayerErrorCategory {
  /// Mid-playback hiccup that *might* resolve on its own (single decode glitch,
  /// brief network stall after some frames already shipped). UI can keep the
  /// player visible and let the caller decide whether to retry.
  transient,

  /// The decoder cannot handle this stream's codec / container at all.
  /// Switching to a different decoder (e.g. video_player → IJK) won't help if
  /// the format itself is the problem; switching *sources* (a transcoded line)
  /// might.
  codecUnsupported,

  /// Network or I/O failure — DNS, TCP, TLS, HTTP, segment 404. The decoder
  /// is fine; the bytes aren't reaching it. Caller should retry the line or
  /// surface "网络不好".
  network,

  /// Permanent failure with no obvious recovery path (server-side player
  /// died, malformed essential metadata, etc.). Don't bother retrying.
  terminal,

  /// Couldn't classify — treat as opaque. Default for video_player errors
  /// where we only get a free-form `errorDescription`.
  unknown,
}

/// Structured error attached to a [NiumaPlayerValue] when `phase == error`.
/// Replaces the previous practice of stuffing `"$code/extra=$extra@${pos}ms"`
/// into a single `errorMessage` string; consumers can now switch on
/// [category] instead of pattern-matching the message.
@immutable
class PlayerError {
  const PlayerError({
    required this.category,
    required this.message,
    this.code,
  });

  final PlayerErrorCategory category;
  final String message;

  /// Native error code when available (e.g. IJK's `what` value as a string).
  /// Diagnostic only; consumers should drive logic off [category].
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

/// Mutually exclusive playback phases. Single source of truth for "what's
/// going on right now"; everything else (`isPlaying`, `isBuffering`,
/// `isCompleted`, `initialized`, `hasError`) is derived from this.
///
/// State machine (forward edges only):
/// ```
///   idle → opening → ready ⇄ playing ⇄ paused
///                             ↘    ↑    ↗
///                              buffering
///   playing/paused/buffering → ended  (when not looping)
///   any → error
/// ```
enum PlayerPhase {
  /// Before [PlayerBackend.initialize] is called. Default state.
  idle,

  /// Native side is preparing the source (demuxer probe, decoder warmup,
  /// first-frame). On Android this maps to `prepareAsync` in flight; the
  /// optional `openingStage` decorates *which* sub-step is running.
  opening,

  /// Prepared, no playback intent yet. Reachable after `opening` completes
  /// successfully. Becomes `playing` on the first `play()`.
  ready,

  /// Actively rendering frames.
  playing,

  /// User-initiated pause. Distinct from `buffering` (which is involuntary).
  paused,

  /// Play intent is active but the decoder is starved for data. UI should
  /// keep the "pause" icon visible because the user *wants* to be playing —
  /// see [NiumaPlayerValue.effectivelyPlaying].
  buffering,

  /// Reached end-of-media without looping. `position == duration`. Native
  /// must NOT enter this when `setLooping(true)` is set — it should loop
  /// back to `playing` transparently instead.
  ended,

  /// Terminal error. `errorMessage` is set.
  error,
}

/// Immutable snapshot of a [NiumaPlayerController]'s state.
///
/// Field set is built around [PlayerPhase] as the single source of truth.
/// The classic boolean accessors (`isPlaying`, `isBuffering`, `isCompleted`,
/// `initialized`, `hasError`) are kept as compatibility getters so consumers
/// written against the previous contract don't break.
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

  /// Empty initial value (before [PlayerBackend.initialize]).
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

  /// How far into [duration] the underlying player has already loaded. Fuels
  /// the "已缓冲段" grey bar on progress indicators.
  final Duration bufferedPosition;

  /// Optional sub-stage descriptor while `phase == opening` (e.g.
  /// `"openInput"`, `"findStreamInfo"`, `"componentOpen"`). Surfaced into
  /// timeout / error messages for diagnostics. Null otherwise.
  final String? openingStage;

  /// Structured error info; non-null only when `phase == error`. Use
  /// [PlayerError.category] to drive retry / fallback / UI decisions.
  final PlayerError? error;

  // ────────────── Compatibility getters (derived from phase) ──────────────

  /// Plain-text error description, kept for callers written before
  /// [PlayerError] existed.
  String? get errorMessage => error?.message;

  /// True once the backend has metadata and is ready to play (or beyond).
  /// Replaces the old explicit `initialized` field — value is now a function
  /// of [phase] so it can never disagree with the rest of the snapshot.
  bool get initialized =>
      phase != PlayerPhase.idle && phase != PlayerPhase.opening;

  bool get isPlaying => phase == PlayerPhase.playing;
  bool get isBuffering => phase == PlayerPhase.buffering;

  /// Whether playback finished naturally without looping. Native is expected
  /// to handle looping internally — when `setLooping(true)`, this should
  /// never become true.
  bool get isCompleted => phase == PlayerPhase.ended;

  bool get hasError => phase == PlayerPhase.error;

  /// User-facing "is the play button hidden?" — true while the user *intends*
  /// to be playing, even if the decoder is momentarily starved. Exists to
  /// replace the old `_intentPlaying && !isCompleted` workaround consumers
  /// had to keep around to suppress flicker during buffering.
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
    // Allow explicit null via a sentinel: pass `clearError: true` to reset.
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

/// Reasons why the controller fell back from video_player to IJK.
enum FallbackReason { error, timeout }

/// Events emitted on [NiumaPlayerController.events] to let the app log or
/// react to backend selection / fallback behaviour.
sealed class NiumaPlayerEvent {
  const NiumaPlayerEvent();
}

/// Fired exactly once per successful [NiumaPlayerController.initialize] with
/// the backend that was ultimately chosen.
final class BackendSelected extends NiumaPlayerEvent {
  const BackendSelected(this.kind, {required this.fromMemory});

  final PlayerBackendKind kind;

  /// true when the selection came from [DeviceMemory] rather than a live try.
  final bool fromMemory;

  @override
  String toString() =>
      'BackendSelected(kind: $kind, fromMemory: $fromMemory)';
}

/// Fired when the controller had to tear down video_player and start IJK
/// because of an error or timeout.
final class FallbackTriggered extends NiumaPlayerEvent {
  const FallbackTriggered(
    this.reason, {
    this.errorCode,
    this.errorCategory,
  });

  final FallbackReason reason;
  final String? errorCode;

  /// Categorisation of the underlying [PlayerError], when available. Lets
  /// downstream selection logic distinguish "decoder couldn't read this"
  /// (worth falling back to IJK) from "the network is down" (no point).
  final PlayerErrorCategory? errorCategory;

  @override
  String toString() =>
      'FallbackTriggered(reason: $reason, errorCode: $errorCode, '
      'errorCategory: $errorCategory)';
}
