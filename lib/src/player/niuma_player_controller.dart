import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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
import 'package:niuma_player/src/cast/cast_session.dart';
import 'package:niuma_player/src/cast/cast_state.dart';
import 'package:niuma_player/src/player/niuma_player_options.dart';
import 'package:niuma_player/src/player/pip_lifecycle_observer.dart';

/// 进程级「正在播放且要求亮屏的 controller 数」，归并多实例，见 `_syncWakelock`。
int _wakelockHolderCount = 0;

/// 播放内核的单一公共门面：选 backend（iOS/Web → video_player，Android →
/// 自家 native 插件，ExoPlayer 失败当次会话回退 IJK）、多线路编排、PiP / 投屏。
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
  /// 注意重试在 Android forceIjk 兜底层之内：最坏 `maxAttempts × 2` 次
  /// 初始化（默认值下约 194s 才暴露失败），收紧上限调低 maxAttempts / initTimeout。
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
        if (_initCompleter == completer) {
          _initCompleter = null;
        }
        // 失败必须同步落到 value（phase=error）：否则调用方没 catch future 时
        // value 驱动的 UI 永远等不到 error 态，用户只看到无限转圈。
        if (!_disposed) {
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
    // iOS / Web → 永远走 video_player。
    if (_platform.isIOS || _platform.isWeb) {
      // autoFailover 开且多线路时按 priority 升序全遍历，否则只试 defaultLine。
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
          await _withRetry(() async {
            // 每次重试：dispose 旧 backend，重跑 middleware（保证 URL/headers 新鲜）。
            await _disposeCurrentBackend();
            _resolvedSource = await runSourceMiddlewares(
              line.source,
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
          return;
        } catch (e, st) {
          lastError = e;
          lastStack = st;
          if (candidates.length > 1) {
            _emit(LineSwitchFailed(toId: line.id, error: e));
          }
        }
      }
      // 所有线路都失败 → 上抛最后一个错误，转成 PlayerPhase.error。
      Error.throwWithStackTrace(lastError!, lastStack ?? StackTrace.current);
    }

    // Android：ExoPlayer 失败时 dispose 后用 forceIjk=true 重开一次。
    if (options.forceIjkOnAndroid) {
      await _initNative(forceIjk: true);
      return;
    }

    try {
      await _initNative(forceIjk: false);
    } catch (exoError) {
      // ExoPlayer 失败 → 当次会话内用 IJK 兜底重试（不落盘）。
      _emit(FallbackTriggered(
        FallbackReason.error,
        errorCode: exoError.toString(),
      ));
      await _disposeCurrentBackend();
      try {
        await _initNative(forceIjk: true);
      } catch (ijkError, st) {
        // 两内核都失败：合成双段错误一起抛，避免 IJK 的错掩盖 Exo 的根因。
        Error.throwWithStackTrace(
          EngineFallbackFailure(primary: exoError, fallback: ijkError),
          st,
        );
      }
    }
  }

  Future<void> _initNative({required bool forceIjk}) async {
    try {
      await _withRetry(() async {
        // 每次重试：dispose 旧 backend，重跑 middleware（保证 URL/headers 新鲜）。
        await _disposeCurrentBackend();
        _resolvedSource = await runSourceMiddlewares(
          source.currentLine.source,
          middlewares,
        );
        final native = _backendFactory.createNative(
          _resolvedSource!,
          forceIjk: forceIjk,
          useAndroidPlatformView: options.useAndroidPlatformView,
        );
        await _attachBackend(native);
        await native.initialize().timeout(options.initTimeout);
      });
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
    final session = _castSession.value;
    if (session != null) {
      await session.play();
      return;
    }
    await _backend?.play();
    // PiP RemoteAction 同步只走 value setter；这里再主动 push 会双调
    // setPictureInPictureParams，导致 OS PiP UI 反复重置闪掉。
  }

  Future<void> pause() async {
    final session = _castSession.value;
    if (session != null) {
      await session.pause();
      return;
    }
    await _backend?.pause();
  }

  Future<void> seekTo(Duration position) async {
    final session = _castSession.value;
    if (session != null) {
      await session.seek(position);
      return;
    }
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
      if (options.rollbackOnSwitchFailure && fromId != lineId) {
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

  /// [switchLine] 与 rollback 共用：dispose 老 backend → middleware →
  /// 新 backend initialize → seek + 续播。
  Future<void> _doSwitchTo(
    String lineId, {
    required Duration savedPos,
    required bool wasPlaying,
  }) async {
    final target = source.lineById(lineId);
    if (target == null) {
      throw ArgumentError.value(lineId, 'lineId', 'unknown line id');
    }
    await _disposeCurrentBackend();
    if (_disposed) return;
    _activeLineId = lineId;
    final resolved = await runSourceMiddlewares(target.source, middlewares);
    if (_disposed) return;
    _resolvedSource = resolved;

    if (_platform.isIOS || _platform.isWeb) {
      await _attachBackend(_backendFactory.createVideoPlayer(resolved));
      if (_disposed) {
        // 刚 attach 的 backend 不能泄漏
        await _disposeCurrentBackend();
        return;
      }
      await _withRetry(
          () => _backend!.initialize().timeout(options.initTimeout));
    } else {
      await _initNative(forceIjk: options.forceIjkOnAndroid);
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
      if (_disposed) return;
    }
  }


  // ────────────── 弹幕显示开关 ──────────────

  /// 弹幕显示开关（默认 `true`）。业务监听它决定是否渲染弹幕层，
  /// dispose 时自动释放。
  final ValueNotifier<bool> danmakuVisibility = ValueNotifier(true);

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

  // ────────────── Cast（投屏） ──────────────

  final ValueNotifier<CastSession?> _castSession =
      ValueNotifier<CastSession?>(null);

  /// 当前投屏会话。null = 未投屏；UI 监听它切换控件远程映射状态。
  ValueListenable<CastSession?> get castSession => _castSession;

  /// 测试辅助：直接 set [_castSession.value]。生产路径走 connectCast。
  @visibleForTesting
  void debugSetCastSession(CastSession? session) {
    _castSession.value = session;
  }

  /// 进入投屏：pause 本地 backend，写入 [castSession]，emit [CastStarted]。
  Future<void> connectCast(CastSession session) async {
    await pause(); // 此时 _castSession 还 null，调本地 backend
    _castSession.value = session;
    if (!_eventController.isClosed) {
      _eventController.add(CastStarted(session.device));
    }
  }

  /// 退出投屏。从 session 拿当前位置；本地 seekTo 接续；emit [CastEnded] 事件。
  Future<void> disconnectCast({
    required CastEndReason reason,
  }) async {
    final session = _castSession.value;
    if (session == null) return;
    Duration? remotePos;
    try {
      remotePos = await session.getPosition();
    } catch (_) {
      remotePos = null;
    }
    try {
      await session.disconnect();
    } catch (_) {}
    _castSession.value = null;
    if (remotePos != null && !_disposed) {
      await seekTo(remotePos);
    }
    if (!_eventController.isClosed) {
      _eventController.add(CastEnded(reason));
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // 仍在播时直接销毁（feed 滑走等）也要退出亮屏计数，不留泄漏。
    _syncWakelock(false);
    if (_pipObserver != null) {
      WidgetsBinding.instance.removeObserver(_pipObserver!);
      _pipObserver = null;
    }
    final session = _castSession.value;
    if (session != null) {
      try {
        await session.disconnect().timeout(const Duration(seconds: 2));
      } catch (_) {
        // 忽略——dispose 中不抛
      }
    }
    await _disposeCurrentBackend();
    await _eventController.close();
    danmakuVisibility.dispose();
    _castSession.dispose();
    super.dispose();
  }
}
