import 'dart:async';
import 'dart:io';

import 'package:video_player/video_player.dart';

import '../domain/data_source.dart';
import '../domain/player_backend.dart';
import '../domain/player_state.dart';

/// [PlayerBackend] implementation wrapping `package:video_player`.
class VideoPlayerBackend implements PlayerBackend {
  VideoPlayerBackend(this._dataSource);

  final NiumaDataSource _dataSource;

  late final VideoPlayerController _inner = _buildController();

  NiumaPlayerValue _value = NiumaPlayerValue.uninitialized();
  final StreamController<NiumaPlayerValue> _valueController =
      StreamController<NiumaPlayerValue>.broadcast();
  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast();

  bool _disposed = false;

  /// The underlying controller, exposed so that [NiumaPlayerView] can hand it
  /// to `package:video_player`'s `VideoPlayer` widget.
  VideoPlayerController get innerController => _inner;

  VideoPlayerController _buildController() {
    final headers = _dataSource.headers ?? const <String, String>{};
    switch (_dataSource.type) {
      case NiumaSourceType.network:
        return VideoPlayerController.networkUrl(
          Uri.parse(_dataSource.uri),
          httpHeaders: headers,
        );
      case NiumaSourceType.asset:
        return VideoPlayerController.asset(_dataSource.uri);
      case NiumaSourceType.file:
        return VideoPlayerController.file(File(_dataSource.uri));
    }
  }

  @override
  PlayerBackendKind get kind => PlayerBackendKind.videoPlayer;

  @override
  int? get textureId => null;

  @override
  NiumaPlayerValue get value => _value;

  @override
  Stream<NiumaPlayerValue> get valueStream => _valueController.stream;

  @override
  Stream<NiumaPlayerEvent> get eventStream => _eventController.stream;

  @override
  Future<void> initialize() async {
    _inner.addListener(_onInnerChanged);
    await _inner.initialize();
  }

  /// Derive [PlayerPhase] from a [VideoPlayerValue].
  ///
  /// Priority is `error → opening → ended → buffering → playing → paused/ready`.
  /// `isCompleted` only fires on video_player when looping is OFF, so we can
  /// trust it as the authoritative end-of-media signal here.
  PlayerPhase _derivePhase(VideoPlayerValue v) {
    if (v.hasError) return PlayerPhase.error;
    if (!v.isInitialized) return PlayerPhase.opening;
    if (v.isCompleted) return PlayerPhase.ended;
    if (v.isBuffering) return PlayerPhase.buffering;
    if (v.isPlaying) return PlayerPhase.playing;
    // Initialized, not playing, not buffering, not ended:
    //   - position == 0  → ready (just opened, never started)
    //   - position > 0   → paused (was playing)
    if (v.position == Duration.zero) return PlayerPhase.ready;
    return PlayerPhase.paused;
  }

  void _onInnerChanged() {
    if (_disposed) return;
    final v = _inner.value;
    // video_player reports buffered as a list of DurationRange segments; the
    // UI cares about "how far have we preloaded" which is the tail of the
    // last segment. Empty list → no buffer info yet.
    final buffered =
        v.buffered.isEmpty ? Duration.zero : v.buffered.last.end;
    final phase = _derivePhase(v);
    // video_player only gives us a free-form `errorDescription` — no error
    // codes, no categorisation. Wrap it as `unknown` so consumers still get
    // a structured [PlayerError] object; switching to IJK is the only real
    // recovery path so detail beyond "yes there was an error" doesn't add
    // value here.
    final PlayerError? playerError = v.hasError
        ? PlayerError(
            category: PlayerErrorCategory.unknown,
            message: v.errorDescription ?? 'video_player error',
          )
        : null;
    final mapped = NiumaPlayerValue(
      phase: phase,
      position: v.position,
      duration: v.duration,
      size: v.size,
      bufferedPosition: buffered,
      error: playerError,
    );
    if (mapped != _value) {
      _value = mapped;
      if (!_valueController.isClosed) {
        _valueController.add(_value);
      }
    }
    if (v.hasError && !_eventController.isClosed) {
      // video_player surfaces errors through `value.errorDescription`; we
      // re-emit as a `FallbackTriggered` so the controller can react.
      _eventController.add(
        FallbackTriggered(
          FallbackReason.error,
          errorCode: v.errorDescription,
          errorCategory: PlayerErrorCategory.unknown,
        ),
      );
    }
  }

  @override
  Future<void> play() => _inner.play();

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> seekTo(Duration position) => _inner.seekTo(position);

  @override
  Future<void> setSpeed(double speed) => _inner.setPlaybackSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _inner.setVolume(volume);

  @override
  Future<void> setLooping(bool looping) => _inner.setLooping(looping);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _inner.removeListener(_onInnerChanged);
    await _inner.dispose();
    await _valueController.close();
    await _eventController.close();
  }
}
