import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:niuma_player/src/capabilities/niuma_capabilities.dart';
import 'package:niuma_player/src/data/default_backend_factory.dart';
import 'package:niuma_player/src/data/default_platform_bridge.dart';
import 'package:niuma_player/src/domain/backend_factory.dart';
import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/platform_bridge.dart';
import 'package:niuma_player/src/domain/player_backend.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/orchestration/multi_source.dart';
import 'package:niuma_player/src/orchestration/retry_policy.dart';
import 'package:niuma_player/src/orchestration/source_middleware.dart';
import 'package:niuma_player/src/player/niuma_player_options.dart';
import 'package:niuma_player/src/player/pip_lifecycle_observer.dart';

/// 进程级「正在播放且要求亮屏的 controller 数」，归并多实例，见 `_syncWakelock`。
int _wakelockHolderCount = 0;

/// 播放内核的单一公共门面：选 backend（三端主路径官方 video_player，web 走
/// 自家 WebVideoBackend，Android 失败当次会话回退 IJK 软解）、多线路编排、
/// PiP。
///
/// 注意：[events] 流和 value 监听器都是**同步** fire——build 期间直接
/// setState 会撞 framework locked，建议用 `ValueListenableBuilder` 消费。
class NiumaPlayerController extends ValueNotifier<NiumaPlayerValue> {
  /// 构造并注册 PiP lifecycle observer。
  NiumaPlayerController(
    NiumaMediaSource source, {
    this.middlewares = const [],
    this.retryPolicy = const RetryPolicy.smart(),
    NiumaPlayerOptions? options,
    PlatformBridge? platform,
    BackendFactory? backendFactory,
  })  : _source = source,
        options = options ?? const NiumaPlayerOptions(),
        _platform = platform ?? const DefaultPlatformBridge(),
        _backendFactory = backendFactory ?? const DefaultBackendFactory(),
        super(NiumaPlayerValue.uninitialized()) {
    // observer 永远注册：autoEnterPip 只控制 shouldEnter()，
    // onResume 兜底重置 stale PiP state 始终生效。
    _pipObserver = PipLifecycleObserver(
      shouldEnter: () =>
          _autoEnterPip &&
          value.phase == PlayerPhase.playing &&
          !value.isInPictureInPicture,
      enter: enterPictureInPicture,
      onResume: _resetStalePipStateOnResume,
    );
    WidgetsBinding.instance.addObserver(_pipObserver!);
  }

  /// 单 source 便捷 factory：把 [ds] 包成 [NiumaMediaSource.single]。
  factory NiumaPlayerController.dataSource(
    NiumaDataSource ds, {
    String? thumbnailVtt,
    NiumaPlayerOptions? options,
    PlatformBridge? platform,
    BackendFactory? backendFactory,
  }) =>
      NiumaPlayerController(
        NiumaMediaSource.single(ds, thumbnailVtt: thumbnailVtt),
        options: options,
        platform: platform,
        backendFactory: backendFactory,
      );

  /// 当前播放线路集的 [NiumaMediaSource]；[load] 原地换源后返回新源。
  NiumaMediaSource get source => _source;
  NiumaMediaSource _source;

  /// backend 起飞前作用于数据源的 middleware 流水线；每次 initialize /
  /// switchLine / 重试都会跑，保证 headers / signed URL 新鲜。
  final List<SourceMiddleware> middlewares;

  /// [initialize] 抛可恢复错误时的重试策略。
  /// 注意重试在 Android IJK 兜底层之内：最坏 `(maxAttempts+1) × 2` 次
  /// 初始化（默认值下约 254s 才暴露失败，autoFailover 多线路再乘线路数），
  /// 收紧上限调低 maxAttempts / initTimeout。
  final RetryPolicy retryPolicy;

  /// 向后兼容访问器：当前激活线路的数据源。
  NiumaDataSource get dataSource => source.currentLine.source;

  /// 行为选项。
  final NiumaPlayerOptions options;

  final PlatformBridge _platform;
  final BackendFactory _backendFactory;

  PlayerBackend? _backend;
  StreamSubscription<NiumaPlayerValue>? _valueSub;
  StreamSubscription<NiumaPlayerEvent>? _eventSub;
  Completer<void>? _initCompleter;
  bool _disposed = false;

  /// 代际号：[load]（非换源路径）与 [dispose] 递增。仍在退避重试中的旧
  /// init 链在下一次 attempt 时发现代际不符即自行终止，防止旧链复活旧源 /
  /// 泄漏新建 backend。
  int _epoch = 0;

  /// 当前激活线路的 id。初始值 = `source.defaultLineId`，[switchLine] 成功后更新。
  String get activeLineId => _activeLineId ?? source.defaultLineId;

  String? _activeLineId;

  /// 经过 [middlewares] 流水线后的数据源。
  NiumaDataSource? _resolvedSource;

  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast(sync: true);

  /// [BackendSelected] / [FallbackTriggered] 等事件的 broadcast stream。
  /// 在 [initialize] 之前订阅是安全的。
  Stream<NiumaPlayerEvent> get events => _eventController.stream;

  /// 当前激活的 Dart 侧 backend 类型；[initialize] 完成前的值无意义，
  /// 调用方应等 `BackendSelected`。
  PlayerBackendKind get activeBackend =>
      _backend?.kind ?? PlayerBackendKind.videoPlayer;

  /// 当前激活 backend 的 texture id；video_player 自管 widget，返回 null。
  int? get textureId => _backend?.textureId;

  /// 底层 backend 实例，供 [NiumaPlayerView] 选择渲染 widget。
  PlayerBackend? get backend => _backend;

  /// 选平台 backend 并初始化。多次调用安全：成功后复用同一 future，
  /// 失败后清缓存让"重试"能完整重跑。
  /// 错误只经 future 传播（不 rethrow，避免 unhandled）。
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
      (_) async {
        // 初始化成功后主动查 PiP 能力——backend 不会自己推支持状态。
        await _queryAndUpdatePipSupport();
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object e, StackTrace st) {
        final isCurrent = _initCompleter == completer;
        if (isCurrent) _initCompleter = null;
        // 失败必须同步落到 value（phase=error）：否则调用方没 catch future 时
        // value 驱动的 UI 永远等不到 error 态，用户只看到无限转圈。
        // 已被 load() 取代的旧链不写——避免覆盖新链的正常状态。
        if (isCurrent && !_disposed) {
          value = value.copyWith(
            phase: PlayerPhase.error,
            error: PlayerError(
              category: _categorize(e),
              message: e.toString(),
            ),
          );
        }
        if (!completer.isCompleted) completer.completeError(e, st);
      },
    );
    return completer.future;
  }

  /// 原地换到新源 [newSource]，尽量复用当前 backend。
  /// web 上复用同一 `<video>` 换 src 可保住 iOS Safari 的有声播放激活；
  /// backend 不支持换源时自动 dispose + 重建。
  Future<void> load(NiumaMediaSource newSource) async {
    if (_disposed) {
      throw StateError('NiumaPlayerController has been disposed');
    }
    _source = newSource;
    _activeLineId = newSource.defaultLineId;
    final backend = _backend;
    if (backend != null && backend.supportsSourceSwap) {
      _resolvedSource =
          await runSourceMiddlewares(newSource.currentLine.source, middlewares);
      await backend.load(_resolvedSource!).timeout(options.initTimeout);
    } else {
      _epoch++; // 作废可能仍在退避重试中的旧 init 链
      await _disposeCurrentBackend();
      _initCompleter = null;
      await initialize();
    }
  }

  /// 把异常分类成 [PlayerErrorCategory]；带 `.category` getter 的对象
  /// duck-typing 分类，测试类无需在生产代码可见。
  PlayerErrorCategory _categorize(Object e) {
    if (e is EngineFallbackFailure) return _categorize(e.fallback);
    if (e is TimeoutException) return PlayerErrorCategory.network;
    try {
      final dynamic d = e;
      final c = d.category;
      if (c is PlayerErrorCategory) return c;
    } catch (_) {
      // 不是带分类的异常
    }
    return PlayerErrorCategory.unknown;
  }

  /// 按 [retryPolicy] 带重试地运行 [bringUp]；不可重试时 rethrow 交给调用方。
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
    // 三端主路径统一走官方 video_player（iOS AVPlayer / Android ExoPlayer /
    // Web <video>，由官方维护、可随意升级）。Android 额外带 IJK 软解兜底。
    if (_platform.isIOS || _platform.isWeb) {
      await _initVideoPlayer();
      return;
    }

    // Android。
    if (options.forceIjkOnAndroid) {
      await _initNative(source.currentLine.source);
      return;
    }
    try {
      await _initVideoPlayer();
    } catch (vpError) {
      // video_player 失败 → 当次会话内用 IJK 软解兜底重试（不落盘）。
      _emit(FallbackTriggered(
        FallbackReason.error,
        errorCode: vpError.toString(),
      ));
      await _disposeCurrentBackend();
      // 多线路遍历会把 _activeLineId 停在最后一条失败线，而 IJK 兜底实际
      // 播的是默认线路——先校正，别让 activeLineId 撒谎。
      _activeLineId = source.defaultLineId;
      try {
        await _initNative(source.currentLine.source);
      } catch (ijkError, st) {
        // 两内核都失败：合成双段错误一起抛，避免 IJK 的错掩盖 vp 的根因。
        Error.throwWithStackTrace(
          EngineFallbackFailure(primary: vpError, fallback: ijkError),
          st,
        );
      }
    }
  }

  /// 单次拉起序列：dispose 旧 backend → 重跑 middleware（URL/headers 新鲜）
  /// → 建新 backend → attach → initialize（带 wall-clock 超时）。
  /// [_initVideoPlayer] / [_initNative] / [_doSwitchTo] 的每次 attempt 共用。
  Future<void> _bringUp(
    int epoch,
    NiumaDataSource raw,
    PlayerBackend Function(NiumaDataSource resolved) create,
  ) async {
    if (_disposed || epoch != _epoch) {
      throw StateError('NiumaPlayerController superseded or disposed');
    }
    await _disposeCurrentBackend();
    _resolvedSource = await runSourceMiddlewares(raw, middlewares);
    await _attachBackend(create(_resolvedSource!));
    await _backend!.initialize().timeout(options.initTimeout);
  }

  PlayerBackend _createVideoPlayer(
    NiumaDataSource resolved,
    bool useAndroidPlatformView,
  ) =>
      _backendFactory.createVideoPlayer(
        resolved,
        useAndroidPlatformView: useAndroidPlatformView,
      );

  /// vp 主路径实际是否用 platformView。Android 9（API 28）上 vp 的平台视图
  /// 走 `setupSurfaceWithCallback`：`surfaceCreated` 里 `seekTo(1)`、
  /// `surfaceDestroyed` 里无条件 `setVideoSurface(null)`（不判断当前绑的是
  /// 不是自己）——全屏 ↔ inline 交接必然黑屏 + 跳回开头，故降级 textureView。
  /// IJK 兜底路径走自家 `PlayerSession.surfaceStack`，不受此限。
  Future<bool> _vpUsePlatformView() async =>
      options.useAndroidPlatformView &&
      await NiumaCapabilities.androidSdkInt() != 28;

  /// video_player 主路径初始化：autoFailover 开且多线路时按 priority 升序
  /// 全遍历，否则只试 defaultLine；全失败抛最后一条错误。
  Future<void> _initVideoPlayer() async {
    final epoch = _epoch;
    final platformView = await _vpUsePlatformView();
    final candidates =
        (options.autoFailoverOnInitialError && source.lines.length > 1)
            ? ([...source.lines]
              ..sort((a, b) => a.priority.compareTo(b.priority)))
            : <MediaLine>[source.currentLine];

    Object? lastError;
    StackTrace? lastStack;
    for (var i = 0; i < candidates.length; i++) {
      final line = candidates[i];
      try {
        _activeLineId = line.id;
        await _withRetry(() => _bringUp(
            epoch, line.source, (r) => _createVideoPlayer(r, platformView)));
        _emit(const BackendSelected(
          PlayerBackendKind.videoPlayer,
          fromMemory: false,
        ));
        return;
      } catch (e, st) {
        if (e is TimeoutException) {
          // 与 IJK 路径一致：wall-clock 超时发独立信号，便于排障区分。
          _emit(const FallbackTriggered(FallbackReason.timeout));
        }
        lastError = e;
        lastStack = st;
        if (candidates.length > 1) {
          _emit(LineSwitchFailed(toId: line.id, error: e));
        }
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack ?? StackTrace.current);
  }

  /// IJK 软解兜底初始化。[raw] 为目标线路的原始数据源——middleware 在每次
  /// attempt 内重跑。
  Future<void> _initNative(NiumaDataSource raw) async {
    final epoch = _epoch;
    try {
      await _withRetry(() => _bringUp(
            epoch,
            raw,
            (resolved) => _backendFactory.createNative(
              resolved,
              useAndroidPlatformView: options.useAndroidPlatformView,
            ),
          ));
    } on TimeoutException {
      // timeout 转成 FallbackTriggered 语义再 rethrow。
      _emit(const FallbackTriggered(FallbackReason.timeout));
      rethrow;
    }
    _emit(BackendSelected(
      PlayerBackendKind.native,
      fromMemory: false,
    ));
  }

  /// 上一次推到 native PiP 的 isPlaying——只在 playing↔paused 边沿同步，
  /// 避免每次 position 更新都发 method channel。
  bool? _lastPipActionsIsPlaying;

  bool _holdsWakelock = false;

  /// playing 边沿同步屏幕常亮；进程级计数归并多实例，
  /// 避免「A 在播、B 暂停时把 A 的亮屏关掉」。
  void _syncWakelock(bool playing) {
    if (!options.manageScreenWakelock) return;
    if (playing == _holdsWakelock) return;
    _holdsWakelock = playing;
    if (playing) {
      _wakelockHolderCount++;
      if (_wakelockHolderCount == 1) {
        unawaited(_platform.setKeepScreenOn(true));
      }
    } else {
      _wakelockHolderCount--;
      if (_wakelockHolderCount == 0) {
        unawaited(_platform.setKeepScreenOn(false));
      }
    }
  }

  @override
  set value(NiumaPlayerValue newValue) {
    final wasPlaying = value.isPlaying;
    final wasInPip = value.isInPictureInPicture;
    super.value = newValue;
    final inPip = newValue.isInPictureInPicture;
    final isPlaying = newValue.isPlaying;
    if (isPlaying != wasPlaying) _syncWakelock(isPlaying);
    if (!wasInPip && inPip) {
      // 刚乐观进 PiP：只 init cache 不 push——native 马上会设完整 params，
      // 双重 setPictureInPictureParams 会让 OS PiP controls 失效。
      _lastPipActionsIsPlaying = isPlaying;
    } else if (inPip &&
        (isPlaying != wasPlaying || _lastPipActionsIsPlaying != isPlaying)) {
      _lastPipActionsIsPlaying = isPlaying;
      unawaited(
        _backend?.updatePictureInPictureActions(isPlaying: isPlaying),
      );
    } else if (!inPip && wasInPip) {
      _lastPipActionsIsPlaying = null;
    }
  }

  Future<void> _attachBackend(PlayerBackend backend) async {
    if (_disposed) {
      // dispose 后仍在跑的重试链造出的 backend 必须就地销毁，否则泄漏
      // 真实平台播放器；StateError 属 unknown 类，各预设 RetryPolicy 均
      // 不重试，僵尸链就此终止。
      await backend.dispose();
      throw StateError('NiumaPlayerController has been disposed');
    }
    await _detachBackend();
    _backend = backend;
    _valueSub = backend.valueStream.listen((v) {
      if (_disposed) return;
      // backend 不知道 platform-level PiP 状态，保留 controller 自己维护的
      // PiP state，否则会被 backend 推的默认 false 覆盖。
      value = v.copyWith(isInPictureInPicture: value.isInPictureInPicture);
    });
    _eventSub = backend.eventStream.listen((e) {
      if (_disposed) return;
      // FallbackTriggered 由 controller 自己发权威版本，丢掉 backend 级的避免重复。
      if (e is FallbackTriggered) return;
      if (e is PipModeChanged) {
        value = value.copyWith(isInPictureInPicture: e.isInPip);
        // 退出 PiP 默认暂停（与 B 站 / YouTube mobile 一致）；业务想续播
        // 自己拦 PipModeChanged(isInPip:false) 调 play()。
        if (!e.isInPip && value.phase == PlayerPhase.playing) {
          unawaited(pause());
        }
        if (!_eventController.isClosed) _eventController.add(e);
        return;
      }
      if (e is PipRemoteAction) {
        if (e.action == 'playPauseToggle') {
          if (value.phase == PlayerPhase.playing) {
            unawaited(pause());
          } else {
            unawaited(play());
          }
        }
        if (!_eventController.isClosed) _eventController.add(e);
        return;
      }
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
    await _backend?.play();
    // PiP RemoteAction 同步只走 value setter；这里再主动 push 会双调
    // setPictureInPictureParams，导致 OS PiP UI 反复重置闪掉。
  }

  Future<void> pause() async {
    await _backend?.pause();
  }

  Future<void> seekTo(Duration position) async {
    await _backend?.seekTo(position);
  }

  /// Web-only：让底层 `<video>` 进浏览器原生 fullscreen（iOS Safari 走
  /// `webkitEnterFullscreen` 进系统 player，Flutter 控件不跟随）。io 平台返 false。
  Future<bool> enterNativeFullscreen() async {
    return await _backend?.enterNativeFullscreen() ?? false;
  }

  /// Web-only：退出浏览器原生 fullscreen。
  Future<bool> exitNativeFullscreen() async {
    return await _backend?.exitNativeFullscreen() ?? false;
  }

  Future<void> setPlaybackSpeed(double speed) async {
    value = value.copyWith(playbackSpeed: speed);
    await _backend?.setSpeed(speed);
  }

  Future<void> setVolume(double volume) async => _backend?.setVolume(volume);
  Future<void> setLooping(bool looping) async => _backend?.setLooping(looping);

  /// Web-only：开 / 关底层 `<video>` 的浏览器原生控件（iOS Safari 上自定义
  /// 控件点不动时的兜底）。非 web 平台为空操作。
  Future<void> setWebNativeControls(bool show) async =>
      _backend?.setWebNativeControls(show);

  /// 切换到 [lineId] 线路：重建 backend 后 seek 回原位置并恢复播放状态。
  /// 成功依次发 [LineSwitching] / [LineSwitched]，失败发 [LineSwitchFailed]
  /// 并 rethrow；未知 id 抛 [ArgumentError]，同线路静默 no-op。
  Future<void> switchLine(String lineId) async {
    if (_disposed) return;
    final target = source.lineById(lineId);
    if (target == null) {
      throw ArgumentError.value(lineId, 'lineId', 'unknown line id');
    }
    final fromId = _activeLineId ?? source.defaultLineId;
    if (fromId == lineId) return;

    _emit(LineSwitching(fromId: fromId, toId: lineId));

    // 切换前快照，回滚复用同一份，保证"切失败 = 什么都没发生"。
    final savedPos = value.position;
    final wasPlaying = value.isPlaying;

    try {
      await _doSwitchTo(lineId, savedPos: savedPos, wasPlaying: wasPlaying);
      _emit(LineSwitched(lineId));
    } catch (e) {
      if (_disposed) return;
      // rollbackOnSwitchFailure：切换失败静默回滚到原线路。
      if (options.rollbackOnSwitchFailure) {
        try {
          await _doSwitchTo(fromId, savedPos: savedPos, wasPlaying: wasPlaying);
          // 回滚成功：发 LineSwitchFailed 供上报，但不 rethrow。
          _emit(LineSwitchFailed(toId: lineId, error: e));
          return;
        } catch (_) {
          // 回滚也失败——掉到原始错误处理。
        }
      }
      _emit(LineSwitchFailed(toId: lineId, error: e));
      rethrow;
    }
  }

  /// [switchLine] 与 rollback 共用：拉起目标线路（重建式重试）→ seek + 续播。
  Future<void> _doSwitchTo(
    String lineId, {
    required Duration savedPos,
    required bool wasPlaying,
  }) async {
    final target = source.lineById(lineId);
    if (target == null) {
      throw ArgumentError.value(lineId, 'lineId', 'unknown line id');
    }
    if (_disposed) return;
    _activeLineId = lineId;

    if (!_platform.isIOS && !_platform.isWeb && options.forceIjkOnAndroid) {
      // Android 且显式强制 IJK——用目标线路的源，别再用默认线。
      await _initNative(target.source);
    } else {
      // 三端统一 video_player 主路径；每次重试整链重建（复用同一个失败
      // backend 反复 initialize 是打不活的）。
      final epoch = _epoch;
      final platformView = await _vpUsePlatformView();
      await _withRetry(() => _bringUp(
          epoch, target.source, (r) => _createVideoPlayer(r, platformView)));
    }
    if (_disposed) {
      await _disposeCurrentBackend();
      return;
    }

    if (savedPos > Duration.zero) {
      await _backend!.seekTo(savedPos);
      if (_disposed) return;
    }
    if (wasPlaying) {
      await _backend!.play();
    }
  }


  // ────────────── PiP（画中画） ──────────────

  bool _autoEnterPip = false;
  PipLifecycleObserver? _pipObserver;

  /// app 切后台时是否自动进 PiP（默认 false）。
  /// 触发条件：app 进 inactive + phase=playing + 不在 PiP 中。
  bool get autoEnterPictureInPictureOnBackground => _autoEnterPip;

  /// 设置 [autoEnterPictureInPictureOnBackground]。只翻 flag，
  /// observer 常驻、由 `shouldEnter` 闭包读它决定是否触发。
  set autoEnterPictureInPictureOnBackground(bool nextValue) {
    if (_autoEnterPip == nextValue) return;
    _autoEnterPip = nextValue;
  }

  /// app 回前台时兜底翻回 stale 的 isInPictureInPicture——部分设备退出 PiP
  /// 时不可靠触发 native 回调。"在前台 = 不在 PiP" 是定义保证。
  void _resetStalePipStateOnResume() {
    if (_disposed) return;
    if (value.isInPictureInPicture) {
      value = value.copyWith(isInPictureInPicture: false);
    }
  }

  /// 进入 PiP。返回 true 表示已发起请求（系统层仍可能拒绝）；
  /// 不支持 / 未 initialize / 已在 PiP → 返回 false 不抛。
  /// 先乐观置 isInPictureInPicture=true 让 UI 提前藏控件（Android 先 resize
  /// 后回调的时序会让控件在迷你窗渲染一帧溢出），失败回滚。
  Future<bool> enterPictureInPicture() async {
    final v = value;
    if (!v.initialized) return false;
    if (v.isInPictureInPicture) return false;
    final backend = _backend;
    if (backend == null) return false;
    value = v.copyWith(isInPictureInPicture: true);
    final aspect = _aspectInts(v.size);
    try {
      final ok = await backend.enterPictureInPicture(
        aspectNum: aspect.$1,
        aspectDen: aspect.$2,
        unsafeAutoBackground: options.unsafePipAutoBackgroundOnEnter,
      );
      if (!ok) {
        value = value.copyWith(isInPictureInPicture: false);
      }
      return ok;
    } catch (_) {
      value = value.copyWith(isInPictureInPicture: false);
      rethrow;
    }
  }

  /// 退出 PiP。不在 PiP 是 no-op，返回 false。
  Future<bool> exitPictureInPicture() async {
    if (!value.isInPictureInPicture) return false;
    final backend = _backend;
    if (backend == null) return false;
    return backend.exitPictureInPicture();
  }

  /// 查 backend 当前的 PiP 设备能力，把结果同步进 value。失败静默忽略。
  Future<void> _queryAndUpdatePipSupport() async {
    final backend = _backend;
    if (backend == null) return;
    try {
      final supported = await backend.queryPictureInPictureSupport();
      if (_disposed) return;
      if (value.isPictureInPictureSupported != supported) {
        value = value.copyWith(isPictureInPictureSupported: supported);
      }
    } catch (_) {
      // 查询失败保持 false（默认值）
    }
  }

  /// 计算 aspect 整数 (num, den)：×1000 整数化 + GCD 约分，fallback 16:9。
  static (int, int) _aspectInts(Size size) {
    if (size.width <= 0 || size.height <= 0) return (16, 9);
    final w = (size.width * 1000).round();
    final h = (size.height * 1000).round();
    final g = _gcd(w, h);
    if (g == 0) return (16, 9);
    return (w ~/ g, h ~/ g);
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _epoch++; // 作废仍在退避重试中的 init 链
    // 仍在播时直接销毁（feed 滑走等）也要退出亮屏计数，不留泄漏。
    _syncWakelock(false);
    if (_pipObserver != null) {
      WidgetsBinding.instance.removeObserver(_pipObserver!);
      _pipObserver = null;
    }
    await _disposeCurrentBackend();
    await _eventController.close();
    super.dispose();
  }
}
