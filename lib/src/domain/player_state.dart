import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'player_backend.dart';

/// Immutable snapshot of a [NiumaPlayerController]'s state. Field set
/// intentionally mirrors `VideoPlayerValue` for drop-in compatibility.
@immutable
class NiumaPlayerValue {
  const NiumaPlayerValue({
    required this.initialized,
    required this.position,
    required this.duration,
    required this.size,
    required this.isPlaying,
    required this.isBuffering,
    this.errorMessage,
  });

  /// Empty initial value (before [NiumaPlayerController.initialize]).
  factory NiumaPlayerValue.uninitialized() => const NiumaPlayerValue(
        initialized: false,
        position: Duration.zero,
        duration: Duration.zero,
        size: Size.zero,
        isPlaying: false,
        isBuffering: false,
      );

  final bool initialized;
  final Duration position;
  final Duration duration;
  final Size size;
  final bool isPlaying;
  final bool isBuffering;
  final String? errorMessage;

  bool get hasError => errorMessage != null;

  double get aspectRatio {
    if (!initialized || size.width == 0 || size.height == 0) {
      return 1.0;
    }
    return size.width / size.height;
  }

  NiumaPlayerValue copyWith({
    bool? initialized,
    Duration? position,
    Duration? duration,
    Size? size,
    bool? isPlaying,
    bool? isBuffering,
    // Allow explicit null via a sentinel: pass `clearError: true` to reset.
    String? errorMessage,
    bool clearError = false,
  }) {
    return NiumaPlayerValue(
      initialized: initialized ?? this.initialized,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      errorMessage:
          clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NiumaPlayerValue &&
        other.initialized == initialized &&
        other.position == position &&
        other.duration == duration &&
        other.size == size &&
        other.isPlaying == isPlaying &&
        other.isBuffering == isBuffering &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
        initialized,
        position,
        duration,
        size,
        isPlaying,
        isBuffering,
        errorMessage,
      );

  @override
  String toString() {
    return 'NiumaPlayerValue('
        'initialized: $initialized, '
        'position: $position, '
        'duration: $duration, '
        'size: $size, '
        'isPlaying: $isPlaying, '
        'isBuffering: $isBuffering, '
        'errorMessage: $errorMessage)';
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
  const FallbackTriggered(this.reason, {this.errorCode});

  final FallbackReason reason;
  final String? errorCode;

  @override
  String toString() =>
      'FallbackTriggered(reason: $reason, errorCode: $errorCode)';
}
