import 'player_state.dart';

/// Which Dart-side backend is currently powering a [NiumaPlayerController].
///
/// Note that `native` covers both ExoPlayer and IJK — those are sub-variants
/// chosen *inside* the Android plugin, not visible at this layer. Use
/// `NiumaPlayerValue.openingStage` / events log for that detail.
enum PlayerBackendKind {
  /// `package:video_player`. Used on iOS (AVPlayer) and Web (`<video>`).
  videoPlayer,

  /// niuma_player's own native plugin. Used on Android. Internally selects
  /// between ExoPlayer (default fast path) and IJK (software-decode rescue);
  /// the choice is opaque to the Dart side except via the `selectedVariant`
  /// field on the backend implementation, surfaced through
  /// [BackendSelected.fromMemory] events for app-level logging.
  native,
}

/// Internal contract every backend (video_player / IJK / test doubles) must
/// implement. [NiumaPlayerController] is written against this abstraction so
/// that fallback is a matter of disposing one instance and constructing the
/// other.
abstract class PlayerBackend {
  /// Identifies which backend this is. Used by the view and by events.
  PlayerBackendKind get kind;

  /// The native texture id, or null if the backend does not expose one (e.g.
  /// video_player on iOS uses its own widget).
  int? get textureId;

  /// Current state snapshot. Updated in lockstep with [valueStream].
  NiumaPlayerValue get value;

  /// Stream of value snapshots. Must emit the initial value on subscription
  /// for convenience (implementations should use broadcast + replay-latest).
  Stream<NiumaPlayerValue> get valueStream;

  /// Backend-level events (currently only errors; controller-level events
  /// such as `BackendSelected` live on the controller, not here).
  Stream<NiumaPlayerEvent> get eventStream;

  Future<void> initialize();

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  Future<void> setSpeed(double speed);

  Future<void> setVolume(double volume);

  Future<void> setLooping(bool looping);

  Future<void> dispose();
}
