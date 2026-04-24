import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/default_backend_factory.dart';
import '../data/default_platform_bridge.dart';
import '../data/device_memory.dart';
import '../domain/backend_factory.dart';
import '../domain/data_source.dart';
import '../domain/platform_bridge.dart';
import '../domain/player_backend.dart';
import '../domain/player_state.dart';

/// Options for tuning [NiumaPlayerController] behaviour. All fields have
/// reasonable defaults so most callers should not need to touch this.
@immutable
class NiumaPlayerOptions {
  const NiumaPlayerOptions({
    this.initTimeout = const Duration(seconds: 5),
    this.memoryTtl = Duration.zero,
    this.forceIjkOnAndroid = false,
  });

  /// If video_player hasn't reached "initialized" within this window we treat
  /// it as a failure and fall back to IJK.
  final Duration initTimeout;

  /// If non-zero, DeviceMemory entries expire after this duration so the
  /// controller will re-probe video_player eventually. `Duration.zero` means
  /// "remember forever".
  final Duration memoryTtl;

  /// Bypasses all heuristics and goes straight to IJK on Android. Useful for
  /// tests and emergency overrides.
  final bool forceIjkOnAndroid;
}

/// Public controller users interact with. Drop-in-ish replacement for
/// `VideoPlayerController`; the Try-Fail-Remember state machine picking
/// between video_player and IJK is implemented here.
class NiumaPlayerController extends ValueNotifier<NiumaPlayerValue> {
  NiumaPlayerController(
    this.dataSource, {
    NiumaPlayerOptions? options,
    PlatformBridge? platform,
    BackendFactory? backendFactory,
    DeviceMemory? deviceMemory,
  })  : options = options ?? const NiumaPlayerOptions(),
        _platform = platform ?? const DefaultPlatformBridge(),
        _backendFactory = backendFactory ?? const DefaultBackendFactory(),
        _deviceMemory = deviceMemory ?? DeviceMemory(),
        super(NiumaPlayerValue.uninitialized());

  final NiumaDataSource dataSource;
  final NiumaPlayerOptions options;

  final PlatformBridge _platform;
  final BackendFactory _backendFactory;
  final DeviceMemory _deviceMemory;

  PlayerBackend? _backend;
  StreamSubscription<NiumaPlayerValue>? _valueSub;
  StreamSubscription<NiumaPlayerEvent>? _eventSub;
  Timer? _initTimeout;
  Completer<void>? _initCompleter;
  bool _fallbackInFlight = false;
  bool _disposed = false;

  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast();

  String? _fingerprint;

  /// Broadcast stream of [BackendSelected] / [FallbackTriggered] events. Safe
  /// to subscribe before [initialize].
  Stream<NiumaPlayerEvent> get events => _eventController.stream;

  /// Which backend is currently active. Before [initialize] completes this
  /// defaults to `videoPlayer` (arbitrary — callers should wait for
  /// `BackendSelected`).
  PlayerBackendKind get activeBackend =>
      _backend?.kind ?? PlayerBackendKind.videoPlayer;

  /// Texture id for the active backend, or null (video_player).
  int? get textureId => _backend?.textureId;

  /// The underlying backend instance. Exposed so [NiumaPlayerView] can pick
  /// the right rendering widget.
  PlayerBackend? get backend => _backend;

  /// Runs the Try-Fail-Remember state machine and leaves [backend] populated.
  /// Safe to call more than once; subsequent calls return the same future.
  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('NiumaPlayerController has been disposed');
    }
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<void>();
    try {
      await _runInitialize();
      if (!_initCompleter!.isCompleted) _initCompleter!.complete();
    } catch (e, st) {
      if (!_initCompleter!.isCompleted) _initCompleter!.completeError(e, st);
      rethrow;
    }
    return _initCompleter!.future;
  }

  Future<void> _runInitialize() async {
    // iOS → always video_player; no fingerprint / memory logic needed.
    if (_platform.isIOS) {
      await _attachBackend(_backendFactory.createVideoPlayer(dataSource));
      await _backend!.initialize();
      _emit(const BackendSelected(
        PlayerBackendKind.videoPlayer,
        fromMemory: false,
      ));
      return;
    }

    // Android path from here on.
    _fingerprint = await _safeFingerprint();

    if (options.forceIjkOnAndroid) {
      await _attachBackend(_backendFactory.createIjk(dataSource));
      await _backend!.initialize();
      _emit(const BackendSelected(
        PlayerBackendKind.ijk,
        fromMemory: false,
      ));
      return;
    }

    if (_fingerprint != null &&
        await _deviceMemory.shouldUseIjk(_fingerprint!)) {
      await _attachBackend(_backendFactory.createIjk(dataSource));
      await _backend!.initialize();
      _emit(const BackendSelected(
        PlayerBackendKind.ijk,
        fromMemory: true,
      ));
      return;
    }

    // Try video_player with a timeout; fall back on error or timeout.
    await _tryVideoPlayerWithFallback();
  }

  Future<String?> _safeFingerprint() async {
    try {
      return await _platform.deviceFingerprint();
    } catch (_) {
      return null;
    }
  }

  Future<void> _tryVideoPlayerWithFallback() async {
    final vp = _backendFactory.createVideoPlayer(dataSource);
    await _attachBackend(vp);

    final fallbackCompleter = Completer<FallbackTriggered?>();

    void maybeSucceed(NiumaPlayerValue v) {
      if (v.initialized && !fallbackCompleter.isCompleted) {
        fallbackCompleter.complete(null);
      }
    }

    void onBackendEvent(NiumaPlayerEvent e) {
      if (e is FallbackTriggered && !fallbackCompleter.isCompleted) {
        fallbackCompleter.complete(e);
      }
    }

    // The shared _valueSub / _eventSub set in _attachBackend already feed our
    // own ValueNotifier; we layer these additional listeners on top so we can
    // observe "initialized" and fallback signals without racing the relay.
    final valueSub = vp.valueStream.listen(maybeSucceed);
    final eventSub = vp.eventStream.listen(onBackendEvent);

    _initTimeout = Timer(options.initTimeout, () {
      if (!fallbackCompleter.isCompleted) {
        fallbackCompleter.complete(
          const FallbackTriggered(FallbackReason.timeout),
        );
      }
    });

    try {
      unawaited(vp.initialize().catchError((Object err) {
        if (!fallbackCompleter.isCompleted) {
          fallbackCompleter.complete(
            FallbackTriggered(
              FallbackReason.error,
              errorCode: err.toString(),
            ),
          );
        }
      }));

      final outcome = await fallbackCompleter.future;
      _initTimeout?.cancel();
      _initTimeout = null;

      if (outcome == null) {
        _emit(const BackendSelected(
          PlayerBackendKind.videoPlayer,
          fromMemory: false,
        ));
        return;
      }

      await _performFallback(outcome);
    } finally {
      await valueSub.cancel();
      await eventSub.cancel();
    }
  }

  Future<void> _performFallback(FallbackTriggered reason) async {
    if (_fallbackInFlight) return;
    _fallbackInFlight = true;
    try {
      if (_fingerprint != null) {
        await _deviceMemory.markIjkNeeded(
          _fingerprint!,
          ttl: options.memoryTtl,
        );
      }
      final old = _backend;
      await _detachBackend();
      await old?.dispose();

      final ijk = _backendFactory.createIjk(dataSource);
      await _attachBackend(ijk);
      await ijk.initialize();
      _emit(reason);
      _emit(const BackendSelected(
        PlayerBackendKind.ijk,
        fromMemory: false,
      ));
    } finally {
      _fallbackInFlight = false;
    }
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
      // `FallbackTriggered` is controller-level: the controller emits its own
      // canonical version inside [_performFallback], so we drop backend-level
      // fallback signals here to avoid duplicates.
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
  /// initialize re-probes video_player instead of going straight to IJK.
  static Future<void> clearDeviceMemory() => DeviceMemory().clear();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _initTimeout?.cancel();
    _initTimeout = null;
    await _detachBackend();
    final b = _backend;
    _backend = null;
    await b?.dispose();
    await _eventController.close();
    super.dispose();
  }
}
