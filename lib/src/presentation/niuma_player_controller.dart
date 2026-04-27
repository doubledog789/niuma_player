import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/default_backend_factory.dart';
import '../data/default_platform_bridge.dart';
import '../data/device_memory.dart' show DeviceMemory;
import '../data/native_backend.dart';
import '../domain/backend_factory.dart';
import '../domain/data_source.dart';
import '../domain/platform_bridge.dart';
import '../domain/player_backend.dart';
import '../domain/player_state.dart';
import '../orchestration/multi_source.dart';
import '../orchestration/source_middleware.dart';

/// Options for tuning [NiumaPlayerController] behaviour. All fields have
/// reasonable defaults so most callers should not need to touch this.
@immutable
class NiumaPlayerOptions {
  const NiumaPlayerOptions({
    this.initTimeout = const Duration(seconds: 30),
    this.forceIjkOnAndroid = false,
  });

  /// If the underlying backend hasn't reached "initialized" within this
  /// window we treat it as a failure and (on Android) retry with IJK.
  ///
  /// Default is generous because the native side already runs its own
  /// no-progress watchdog (20s); this is the absolute wall-clock cap.
  final Duration initTimeout;

  /// On Android, bypass the ExoPlayer fast path and go straight to IJK.
  /// Useful for emergency overrides or A/B testing the rescue path. iOS
  /// and Web ignore this flag (they always use video_player).
  final bool forceIjkOnAndroid;
}

/// Public controller users interact with.
///
/// Selection rules:
///   - iOS / Web → `package:video_player` (AVPlayer / `<video>` + hls.js)
///   - Android   → niuma_player's native plugin
///
/// On Android the native plugin internally chooses between ExoPlayer and
/// IJK based on its persistent `DeviceMemoryStore`. If ExoPlayer fails
/// during opening, the native side persistently marks the device as
/// "needs IJK" and this controller transparently retries once with
/// `forceIjk=true` — the user just sees a brief delay before playback
/// starts.
///
/// Multi-line playback (CDN failover, quality variants) is supported via
/// [NiumaMediaSource]. For single-URL use cases, prefer the
/// [NiumaPlayerController.dataSource] convenience factory.
class NiumaPlayerController extends ValueNotifier<NiumaPlayerValue> {
  NiumaPlayerController(
    this.source, {
    this.middlewares = const [],
    NiumaPlayerOptions? options,
    PlatformBridge? platform,
    BackendFactory? backendFactory,
  })  : options = options ?? const NiumaPlayerOptions(),
        _platform = platform ?? const DefaultPlatformBridge(),
        _backendFactory = backendFactory ?? const DefaultBackendFactory(),
        super(NiumaPlayerValue.uninitialized());

  /// Single-source convenience factory. Wraps the [ds] in a
  /// [NiumaMediaSource.single] so callers without multi-line needs can keep
  /// the simpler ergonomics.
  factory NiumaPlayerController.dataSource(
    NiumaDataSource ds, {
    NiumaPlayerOptions? options,
    PlatformBridge? platform,
    BackendFactory? backendFactory,
  }) =>
      NiumaPlayerController(
        NiumaMediaSource.single(ds),
        options: options,
        platform: platform,
        backendFactory: backendFactory,
      );

  /// The [NiumaMediaSource] describing all available playback lines for this
  /// controller. Pass a [NiumaMediaSource.single] for single-URL playback, or
  /// a [NiumaMediaSource.lines] for quality/CDN switching.
  final NiumaMediaSource source;

  /// Optional middleware pipeline applied to the data source before each
  /// backend bring-up. Runs on every `initialize`, every `switchLine`
  /// (Task 25), and every retry (Task 26) — guarantees fresh headers /
  /// signed URLs.
  final List<SourceMiddleware> middlewares;

  /// Backwards-compatible accessor for callers that only use a single line.
  /// Returns the data source of the currently active line.
  NiumaDataSource get dataSource => source.currentLine.source;
  final NiumaPlayerOptions options;

  final PlatformBridge _platform;
  final BackendFactory _backendFactory;

  PlayerBackend? _backend;
  StreamSubscription<NiumaPlayerValue>? _valueSub;
  StreamSubscription<NiumaPlayerEvent>? _eventSub;
  Completer<void>? _initCompleter;
  bool _disposed = false;

  /// The data source after running through the [middlewares] pipeline.
  /// Populated at the start of [_runInitialize] and reused by [_initNative].
  NiumaDataSource? _resolvedSource;

  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast();

  /// Broadcast stream of [BackendSelected] / [FallbackTriggered] events. Safe
  /// to subscribe before [initialize].
  Stream<NiumaPlayerEvent> get events => _eventController.stream;

  /// Which Dart-side backend is currently active. Before [initialize]
  /// completes this defaults to `videoPlayer` (arbitrary — callers should
  /// wait for `BackendSelected`).
  PlayerBackendKind get activeBackend =>
      _backend?.kind ?? PlayerBackendKind.videoPlayer;

  /// Texture id for the active backend, or null (video_player doesn't expose
  /// one — it manages its own widget).
  int? get textureId => _backend?.textureId;

  /// The underlying backend instance. Exposed so [NiumaPlayerView] can pick
  /// the right rendering widget.
  PlayerBackend? get backend => _backend;

  /// Drives the platform-specific selection and leaves [backend] populated.
  /// Safe to call more than once; subsequent calls return the same future.
  ///
  /// Errors are propagated through the cached completer's future rather
  /// than rethrown: the cached future is the *only* listener, and calling
  /// `rethrow` here would also surface the error as unhandled because the
  /// completer's future would never gain a second subscriber.
  Future<void> initialize() {
    if (_disposed) {
      return Future<void>.error(
        StateError('NiumaPlayerController has been disposed'),
      );
    }
    if (_initCompleter != null) return _initCompleter!.future;
    final completer = Completer<void>();
    _initCompleter = completer;
    _runInitialize().then(
      (_) {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object e, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      },
    );
    return completer.future;
  }

  Future<void> _runInitialize() async {
    // Resolve middlewares once; both iOS/Web and Android paths share the result.
    _resolvedSource = await runSourceMiddlewares(
      source.currentLine.source,
      middlewares,
    );

    // iOS / Web → always video_player.
    if (_platform.isIOS || _platform.isWeb) {
      await _attachBackend(
          _backendFactory.createVideoPlayer(_resolvedSource!));
      await _backend!.initialize().timeout(options.initTimeout);
      _emit(const BackendSelected(
        PlayerBackendKind.videoPlayer,
        fromMemory: false,
      ));
      return;
    }

    // Android: single native backend. The Dart-side retry logic below is
    // the entirety of the Try-Fail-Remember mechanism — native picks the
    // initial variant and persists "needs IJK" itself, so all we have to
    // do is dispose-and-reopen with `forceIjk=true` if the first attempt
    // fails for any non-final reason.
    if (options.forceIjkOnAndroid) {
      await _initNative(forceIjk: true);
      return;
    }

    try {
      await _initNative(forceIjk: false);
    } catch (e) {
      // First attempt failed. Native should have already marked memory if
      // the cause was a codec issue; either way we retry with forceIjk to
      // make sure the user gets *something* playing if IJK can handle it.
      _emit(FallbackTriggered(
        FallbackReason.error,
        errorCode: e.toString(),
      ));
      await _disposeCurrentBackend();
      await _initNative(forceIjk: true);
    }
  }

  Future<void> _initNative({required bool forceIjk}) async {
    final native = _backendFactory.createNative(
      _resolvedSource ?? source.currentLine.source,
      forceIjk: forceIjk,
    );
    await _attachBackend(native);
    try {
      await native.initialize().timeout(options.initTimeout);
    } on TimeoutException {
      // Convert the wall-clock timeout into the FallbackTriggered semantic
      // the public events stream expects, then rethrow so the caller's
      // retry path runs.
      _emit(const FallbackTriggered(FallbackReason.timeout));
      rethrow;
    }
    final fromMemory =
        native is NativeBackend ? native.fromMemory : false;
    _emit(BackendSelected(
      PlayerBackendKind.native,
      fromMemory: fromMemory,
    ));
  }

  Future<void> _attachBackend(PlayerBackend backend) async {
    await _detachBackend();
    _backend = backend;
    _valueSub = backend.valueStream.listen((v) {
      if (_disposed) return;
      value = v;
    });
    _eventSub = backend.eventStream.listen((e) {
      if (_disposed) return;
      // `FallbackTriggered` is controller-level: the controller emits its
      // own canonical version inside [_runInitialize], so we drop
      // backend-level fallback signals here to avoid duplicates.
      if (e is FallbackTriggered) return;
      if (!_eventController.isClosed) {
        _eventController.add(e);
      }
    });
  }

  Future<void> _detachBackend() async {
    await _valueSub?.cancel();
    _valueSub = null;
    await _eventSub?.cancel();
    _eventSub = null;
  }

  Future<void> _disposeCurrentBackend() async {
    final old = _backend;
    await _detachBackend();
    _backend = null;
    await old?.dispose();
  }

  void _emit(NiumaPlayerEvent event) {
    if (_eventController.isClosed) return;
    _eventController.add(event);
  }

  Future<void> play() async {
    debugPrint(
      '[niuma_player] play() backend=${_backend?.kind.name ?? "<null>"}',
    );
    await _backend?.play();
  }

  Future<void> pause() async {
    debugPrint(
      '[niuma_player] pause() backend=${_backend?.kind.name ?? "<null>"}',
    );
    await _backend?.pause();
  }

  Future<void> seekTo(Duration position) async => _backend?.seekTo(position);
  Future<void> setPlaybackSpeed(double speed) async =>
      _backend?.setSpeed(speed);
  Future<void> setVolume(double volume) async => _backend?.setVolume(volume);
  Future<void> setLooping(bool looping) async => _backend?.setLooping(looping);

  /// Wipes the "this device needs IJK" memory for every device fingerprint.
  /// App-level "clear cache / reset" flows should call this so a future
  /// initialize re-probes ExoPlayer instead of going straight to IJK.
  static Future<void> clearDeviceMemory() => DeviceMemory().clear();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _disposeCurrentBackend();
    await _eventController.close();
    super.dispose();
  }
}
