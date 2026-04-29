import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
import '../orchestration/retry_policy.dart';
import '../orchestration/source_middleware.dart';
import '../orchestration/thumbnail_cache.dart';
import '../orchestration/thumbnail_resolver.dart';
import '../orchestration/thumbnail_track.dart';
import '../orchestration/webvtt_parser.dart';

/// Function shape for fetching a WebVTT body.
///
/// Defaults to a thin wrapper over `http.get`. Tests inject a fake to avoid
/// real network calls. Throwing or returning a non-VTT body is safe — the
/// controller treats any failure as "thumbnails disabled" and continues to
/// play the video normally.
typedef ThumbnailFetcher = Future<String> Function(
  Uri uri,
  Map<String, String> headers,
);

/// Hard wall-clock cap on the default VTT fetch. Anything beyond this is
/// treated as a hung server and the thumbnail track is silently disabled
/// (failing-open—video keeps playing).
const Duration kThumbnailFetchTimeout = Duration(seconds: 30);

/// Hard cap on the VTT body size. A 5MB VTT would already imply tens of
/// thousands of cues; anything past this is almost certainly a malicious
/// or misconfigured server. Reject early so the VM doesn't unbounded-eat RAM.
const int kThumbnailMaxBodyBytes = 5 * 1024 * 1024;

Future<String> _defaultThumbnailFetcher(
  Uri uri,
  Map<String, String> headers,
) =>
    fetchThumbnailVtt(uri, headers, http.Client());

/// Internal helper exposed for testing: fetches a VTT body using the given
/// [client]. Honours the global [kThumbnailFetchTimeout] and
/// [kThumbnailMaxBodyBytes] caps; throws [http.ClientException] on
/// non-2xx, oversized body, or timeout.
///
/// In production [_defaultThumbnailFetcher] passes a fresh `http.Client()`;
/// tests can pass a `MockClient` to drive the size cap / timeout / error
/// branches without touching the network.
@visibleForTesting
Future<String> fetchThumbnailVtt(
  Uri uri,
  Map<String, String> headers,
  http.Client client,
) async {
  try {
    final response =
        await client.get(uri, headers: headers).timeout(kThumbnailFetchTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'thumbnail VTT fetch failed: HTTP ${response.statusCode}',
        uri,
      );
    }
    if (response.bodyBytes.length > kThumbnailMaxBodyBytes) {
      throw http.ClientException(
        'thumbnail VTT body too large: '
        '${response.bodyBytes.length} bytes (max $kThumbnailMaxBodyBytes)',
        uri,
      );
    }
    return response.body;
  } finally {
    client.close();
  }
}

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
///
/// **事件 / 值通知是同步触发的**：[events] 流和这个 controller（作为
/// [ValueNotifier]）的监听器在 backend 推上来事件 / 值变更时**同步** fire。
/// 如果监听端在 build / layout / paint 阶段直接调 `setState` 会撞
/// `'setState() or markNeedsBuild() called during build'`（framework is
/// locked）。建议消费方式：
/// 1. **`ValueListenableBuilder`** 包住要响应 [value] 的 widget——框架
///    自动调度 rebuild，不需要手写 listener。
/// 2. **`events` 监听里手动检测** [SchedulerBinding.schedulerPhase]，
///    在 `idle` 之外的相位用 `addPostFrameCallback` 把 setState 延后到
///    下一帧。
/// 3. 参考 `example/lib/thumbnail_demo_page.dart` 的 `_safeSetState`
///    封装——把"如果在 build / layout 阶段就 post-frame 延后，否则同步
///    setState" 这套防御封装成助手函数，所有事件监听都过它。
class NiumaPlayerController extends ValueNotifier<NiumaPlayerValue> {
  NiumaPlayerController(
    this.source, {
    this.middlewares = const [],
    this.retryPolicy = const RetryPolicy.smart(),
    NiumaPlayerOptions? options,
    PlatformBridge? platform,
    BackendFactory? backendFactory,
    ThumbnailFetcher? thumbnailFetcher,
  })  : options = options ?? const NiumaPlayerOptions(),
        _platform = platform ?? const DefaultPlatformBridge(),
        _backendFactory = backendFactory ?? const DefaultBackendFactory(),
        _thumbnailFetcher = thumbnailFetcher ?? _defaultThumbnailFetcher,
        _thumbnailLoadState = source.thumbnailVtt == null
            ? ThumbnailLoadState.none
            : ThumbnailLoadState.idle,
        super(NiumaPlayerValue.uninitialized());

  /// Single-source convenience factory. Wraps the [ds] in a
  /// [NiumaMediaSource.single] so callers without multi-line needs can keep
  /// the simpler ergonomics.
  factory NiumaPlayerController.dataSource(
    NiumaDataSource ds, {
    String? thumbnailVtt,
    NiumaPlayerOptions? options,
    PlatformBridge? platform,
    BackendFactory? backendFactory,
    ThumbnailFetcher? thumbnailFetcher,
  }) =>
      NiumaPlayerController(
        NiumaMediaSource.single(ds, thumbnailVtt: thumbnailVtt),
        options: options,
        platform: platform,
        backendFactory: backendFactory,
        thumbnailFetcher: thumbnailFetcher,
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

  /// Retry policy applied when [initialize] throws a recoverable error
  /// (network / transient by default). Caps at the policy's [RetryPolicy.maxAttempts];
  /// if all attempts fail, the error propagates and triggers the existing
  /// Android forceIjk Try-Fail-Remember fallback.
  ///
  /// **Trade-off**: retry runs *inside* the forceIjk fallback layer. In the
  /// worst case, a single user-visible [initialize] call may make up to
  /// `maxAttempts × 2` total backend initialisation attempts — first
  /// `maxAttempts` ExoPlayer attempts, then `maxAttempts` IJK attempts.
  ///
  /// Worst case wall-clock budget for a never-completing initialize:
  /// `maxAttempts × initTimeout × 2 + sum(backoff) × 2`. With the defaults
  /// (`initTimeout: 30s`, `maxAttempts: 3`, exponential 1s + 2s + 4s = 7s),
  /// that is `(3 × 30 + 7) × 2 ≈ 194s` before failure surfaces. To tighten
  /// the bound, lower [RetryPolicy.maxAttempts], lower
  /// [NiumaPlayerOptions.initTimeout], or pass [RetryPolicy.none] to trade
  /// resilience for latency.
  final RetryPolicy retryPolicy;

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

  /// Tracks the id of the currently active line so [switchLine] can emit the
  /// correct [LineSwitching.fromId]. Updated by [switchLine] on success.
  String? _activeLineId;

  /// The data source after running through the [middlewares] pipeline.
  /// Populated at the start of [_runInitialize] and reused by [_initNative].
  NiumaDataSource? _resolvedSource;

  // ----- Thumbnail (M8) -----
  final ThumbnailCache _thumbnailCache = ThumbnailCache();
  List<WebVttCue> _thumbnailCues = const <WebVttCue>[];
  String? _resolvedThumbnailUrl;
  final ThumbnailFetcher _thumbnailFetcher;
  ThumbnailLoadState _thumbnailLoadState;

  /// In-flight load future — used to dedup concurrent calls to
  /// [_loadThumbnailsIfAny] so multiple `unawaited(...)` triggers only
  /// ever do one fetch.
  Future<void>? _thumbnailLoadFuture;

  /// 当前缩略图加载状态。详见 [ThumbnailLoadState] 文档。
  ///
  /// 状态变更**不会**触发 ValueNotifier 通知或 events 流广播——避免和
  /// player 自身的 value / 事件混在一起。如果上层需要响应这个状态：
  /// 1. 在 build 时直接读这个 getter；
  /// 2. 围绕 player 自身的 events 做轮询（loading→ready 通常 < 100ms）；
  /// 3. 简单 setState 后让 [thumbnailFor] 返回值自然反映"暂时还没好"。
  ThumbnailLoadState get thumbnailLoadState => _thumbnailLoadState;

  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast(sync: true);

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

  /// Classifies an exception into a [PlayerErrorCategory] for retry decisions.
  ///
  /// [TimeoutException] maps to [PlayerErrorCategory.network]. Objects that
  /// carry a `.category` getter of type [PlayerErrorCategory] (e.g., the test
  /// helper `_RetryableError`) are classified via that getter using duck-typing,
  /// so the test class never needs to be visible in production code.
  PlayerErrorCategory _categorize(Object e) {
    if (e is TimeoutException) return PlayerErrorCategory.network;
    try {
      final dynamic d = e;
      final c = d.category;
      if (c is PlayerErrorCategory) return c;
    } catch (_) {
      // not a categorized exception; fall through
    }
    return PlayerErrorCategory.unknown;
  }

  /// Runs [bringUp] with retry according to [retryPolicy].
  ///
  /// On each throw, classifies the error via [_categorize] and asks
  /// [retryPolicy] whether to retry. If not, the exception is rethrown
  /// immediately so the caller's error-handling path (e.g. forceIjk fallback)
  /// can take over.
  Future<T> _withRetry<T>(Future<T> Function() bringUp) async {
    var attempt = 1;
    while (true) {
      try {
        return await bringUp();
      } catch (e) {
        final category = _categorize(e);
        if (!retryPolicy.shouldRetry(category, attempt: attempt)) rethrow;
        await Future<void>.delayed(retryPolicy.delayFor(attempt));
        attempt++;
      }
    }
  }

  Future<void> _runInitialize() async {
    // iOS / Web → always video_player.
    if (_platform.isIOS || _platform.isWeb) {
      await _withRetry(() async {
        // Each retry attempt: dispose any prior (failed) backend, re-run the
        // middleware pipeline (so signed URLs / fresh headers are recomputed),
        // build a fresh backend, then call initialize().
        await _disposeCurrentBackend();
        _resolvedSource = await runSourceMiddlewares(
          source.currentLine.source,
          middlewares,
        );
        await _attachBackend(
            _backendFactory.createVideoPlayer(_resolvedSource!));
        await _backend!.initialize().timeout(options.initTimeout);
      });
      _emit(const BackendSelected(
        PlayerBackendKind.videoPlayer,
        fromMemory: false,
      ));
      unawaited(_loadThumbnailsIfAny());
      return;
    }

    // Android: single native backend. The Dart-side retry logic below is
    // the entirety of the Try-Fail-Remember mechanism — native picks the
    // initial variant and persists "needs IJK" itself, so all we have to
    // do is dispose-and-reopen with `forceIjk=true` if the first attempt
    // fails for any non-final reason.
    if (options.forceIjkOnAndroid) {
      await _initNative(forceIjk: true);
      unawaited(_loadThumbnailsIfAny());
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
    unawaited(_loadThumbnailsIfAny());
  }

  /// Loads + parses the optional [NiumaMediaSource.thumbnailVtt] in the
  /// background. Failures are swallowed (logged via [debugPrint]) so video
  /// playback is never affected by a broken thumbnail track.
  ///
  /// Idempotent: concurrent invocations share a single in-flight future
  /// (I6). After completion the future is reset to null so a future call —
  /// e.g. after a configured retry — could in principle re-attempt; today
  /// nothing in the controller does that, but the door is open.
  Future<void> _loadThumbnailsIfAny() {
    if (_thumbnailLoadFuture != null) return _thumbnailLoadFuture!;
    final fut = _runThumbnailLoad();
    _thumbnailLoadFuture = fut;
    return fut;
  }

  Future<void> _runThumbnailLoad() async {
    final url = source.thumbnailVtt;
    if (url == null) return;
    _thumbnailLoadState = ThumbnailLoadState.loading;
    try {
      final ds = await runSourceMiddlewares(
        NiumaDataSource.network(url),
        middlewares,
      );
      if (_disposed) return;
      final body = await _thumbnailFetcher(
        Uri.parse(ds.uri),
        ds.headers ?? const <String, String>{},
      );
      if (_disposed) return;
      final cues = WebVttParser.parseThumbnails(body);
      if (_disposed) return;
      // 顺序很关键：解析完成后才把两个状态字段（cues + resolvedUrl）一起设进去。
      // 这样 thumbnailFor 看到 _thumbnailCues 非空时也一定有 _resolvedThumbnailUrl。
      _thumbnailCues = cues;
      _resolvedThumbnailUrl = ds.uri;
      _thumbnailLoadState = ThumbnailLoadState.ready;
    } catch (e) {
      // I5: catch 块进入前先检查 _disposed —— dispose 中途完成的 fetcher
      // 不应该再写已 disposed 的字段。
      if (_disposed) return;
      debugPrint('[niuma_player] thumbnail VTT 加载失败：$e（不影响播放）');
      // I9: 同时清掉两个状态字段，避免 partial state（cues 空但 resolvedUrl 有值）。
      _thumbnailCues = const <WebVttCue>[];
      _resolvedThumbnailUrl = null;
      _thumbnailLoadState = ThumbnailLoadState.failed;
    }
  }

  /// 根据当前播放位置 [position] 返回对应的 [ThumbnailFrame]，没有命中或缩略图
  /// 还未就绪时返回 `null`。
  ///
  /// 安全调用：在 [initialize] 之前 / 缩略图加载失败 / 没配置 thumbnailVtt
  /// 都会返回 `null`。**在所有合法输入下不抛**——实现内部 [ThumbnailResolver]
  /// 已用 try/catch 防御 `Uri.parse` 等可抛点；但极端非法输入（例如自行
  /// 构造 cue 时传入 NaN 时间）仍可能触发 framework-level 异常，调用方
  /// 不应依赖"绝对不抛"的强保证。
  ThumbnailFrame? thumbnailFor(Duration position) {
    if (_thumbnailCues.isEmpty || _resolvedThumbnailUrl == null) return null;
    return ThumbnailResolver.resolve(
      position: position,
      cues: _thumbnailCues,
      baseUrl: _resolvedThumbnailUrl!,
      cache: _thumbnailCache,
    );
  }

  Future<void> _initNative({required bool forceIjk}) async {
    PlayerBackend? lastBackend;
    try {
      await _withRetry(() async {
        // Each retry attempt: dispose any prior (failed) backend, re-run the
        // middleware pipeline (so signed URLs / fresh headers are recomputed),
        // build a fresh native backend, then call initialize().
        await _disposeCurrentBackend();
        _resolvedSource = await runSourceMiddlewares(
          source.currentLine.source,
          middlewares,
        );
        final native = _backendFactory.createNative(
          _resolvedSource!,
          forceIjk: forceIjk,
        );
        lastBackend = native;
        await _attachBackend(native);
        await native.initialize().timeout(options.initTimeout);
      });
    } on TimeoutException {
      // Convert the wall-clock timeout into the FallbackTriggered semantic
      // the public events stream expects, then rethrow so the caller's
      // retry path runs.
      _emit(const FallbackTriggered(FallbackReason.timeout));
      rethrow;
    }
    final native = lastBackend;
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

  /// Switches playback to the line identified by [lineId].
  ///
  /// Saves the current playback position and `isPlaying` state, tears down
  /// the active backend, runs the middleware pipeline against the new line's
  /// source, brings up a fresh backend for the target line, seeks back to the
  /// saved position (if non-zero), and resumes playback if the player was
  /// playing before the switch.
  ///
  /// Events emitted (in order on success):
  ///   1. [LineSwitching] — backend tear-down is about to begin.
  ///   2. [LineSwitched]  — new backend is ready.
  ///
  /// On failure, [LineSwitchFailed] is emitted and the error is rethrown.
  ///
  /// Throws [ArgumentError] if [lineId] is not present in [source]'s lines.
  /// No-ops silently if [lineId] equals the currently active line.
  Future<void> switchLine(String lineId) async {
    if (_disposed) return;
    final target = source.lineById(lineId);
    if (target == null) {
      throw ArgumentError.value(lineId, 'lineId', 'unknown line id');
    }
    final fromId = _activeLineId ?? source.defaultLineId;
    if (fromId == lineId) return;

    _emit(LineSwitching(fromId: fromId, toId: lineId));

    final savedPos = value.position;
    final wasPlaying = value.isPlaying;

    try {
      await _disposeCurrentBackend();
      if (_disposed) return;
      _activeLineId = lineId;
      final resolved = await runSourceMiddlewares(target.source, middlewares);
      if (_disposed) return;
      _resolvedSource = resolved;

      if (_platform.isIOS || _platform.isWeb) {
        await _attachBackend(_backendFactory.createVideoPlayer(resolved));
        if (_disposed) {
          // The backend we just attached must not leak; tear it down before
          // bailing.
          await _disposeCurrentBackend();
          return;
        }
        await _withRetry(
            () => _backend!.initialize().timeout(options.initTimeout));
      } else {
        await _initNative(forceIjk: options.forceIjkOnAndroid);
      }
      if (_disposed) {
        // Backend reached "initialized" but the controller was disposed
        // mid-flight — clean up and bail without emitting LineSwitched.
        await _disposeCurrentBackend();
        return;
      }

      if (savedPos > Duration.zero) {
        await _backend!.seekTo(savedPos);
        if (_disposed) return;
      }
      if (wasPlaying) {
        await _backend!.play();
        if (_disposed) return;
      }
      _emit(LineSwitched(lineId));
    } catch (e) {
      if (_disposed) return;
      _emit(LineSwitchFailed(toId: lineId, error: e));
      rethrow;
    }
  }

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
    _thumbnailCache.clear();
    super.dispose();
  }
}
