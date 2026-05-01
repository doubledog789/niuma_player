import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
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
import 'pip_lifecycle_observer.dart';

/// 拉取 WebVTT body 的函数签名。
///
/// 默认是 `http.get` 的薄封装。测试注入 fake 避免真实网络调用。
/// 抛异常或返回非 VTT body 都是安全的——controller 把任何失败视为
/// "thumbnails 关闭"，正常继续播放视频。
typedef ThumbnailFetcher = Future<String> Function(
  Uri uri,
  Map<String, String> headers,
);

/// 暴露给测试用的内部 helper：用给定的 [client] 流式拉取 VTT body，
/// 遵守 [timeout]（wall-clock）和 [maxBytes]（body 大小上限）。
///
/// 实现使用 [http.Client.send]（不是 `client.get`），因此在做 size cap
/// 检查之前**不会**把 body 完整 buffer 到内存。流程是：
///   1. 打开响应流 + 给 headers 阶段加 [timeout]；
///   2. 拒绝非 2xx 状态码；
///   3. 如果服务器声明了 `Content-Length` 且已超过 [maxBytes]，
///      在读 body 前直接拒绝；
///   4. 否则边累积 chunk 边检查；一旦累计超过 [maxBytes] 立即中止——
///      恶意服务器无法骗 VM 先 buffer 任意字节。
///
/// 非 2xx、超大 body、timeout 都抛 [http.ClientException]。
/// 生产环境中 controller 的默认 fetcher（由 `_makeDefaultThumbnailFetcher`
/// 构造）传入一个新 `http.Client()`；测试可以传 `MockClient` 来驱动
/// size cap / timeout / error 分支，不用碰真实网络。
@visibleForTesting
Future<String> fetchThumbnailVtt(
  Uri uri,
  Map<String, String> headers,
  http.Client client, {
  Duration timeout = const Duration(seconds: 30),
  int maxBytes = 5 * 1024 * 1024,
}) async {
  try {
    final request = http.Request('GET', uri);
    request.headers.addAll(headers);
    final streamed = await client.send(request).timeout(timeout);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw http.ClientException(
        'thumbnail VTT fetch failed: HTTP ${streamed.statusCode}',
        uri,
      );
    }
    // 服务器诚实声明 Content-Length 时利用它：在读 body 之前就可以
    // 拒绝。
    final declared = streamed.contentLength;
    if (declared != null && declared > maxBytes) {
      throw http.ClientException(
        'thumbnail VTT body too large per Content-Length: '
        '$declared (max $maxBytes)',
        uri,
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw http.ClientException(
          'thumbnail VTT body exceeded $maxBytes bytes during streaming',
          uri,
        );
      }
    }
    return utf8.decode(builder.toBytes());
  } finally {
    client.close();
  }
}

/// 构造调用方未注入自定义 fetcher 时使用的默认 [ThumbnailFetcher]
/// 闭包。捕获 [options]，使每个 controller 自己的 timeout / size cap
/// 设置能透到 [fetchThumbnailVtt]。
ThumbnailFetcher _makeDefaultThumbnailFetcher(NiumaPlayerOptions options) {
  return (uri, headers) => fetchThumbnailVtt(
        uri,
        headers,
        http.Client(),
        timeout: options.thumbnailFetchTimeout,
        maxBytes: options.thumbnailMaxBodyBytes,
      );
}

/// 调整 [NiumaPlayerController] 行为的选项。所有字段都有合理默认值，
/// 大多数调用方无需触碰。
@immutable
class NiumaPlayerOptions {
  const NiumaPlayerOptions({
    this.initTimeout = const Duration(seconds: 30),
    this.forceIjkOnAndroid = false,
    this.thumbnailFetchTimeout = const Duration(seconds: 30),
    this.thumbnailMaxBodyBytes = 5 * 1024 * 1024,
  });

  /// 若底层 backend 在该窗口内还没到 "initialized"，视作失败，
  /// （Android 上）以 IJK 重试。
  ///
  /// 默认值给得宽松，因为 native 侧已自带 no-progress watchdog（20s）；
  /// 这里是绝对的 wall-clock 上限。
  final Duration initTimeout;

  /// Android 上绕过 ExoPlayer 快路径直接走 IJK。
  /// 用于紧急覆盖或 A/B 测试兜底路径。iOS 和 Web 忽略本标志
  /// （永远走 video_player）。
  final bool forceIjkOnAndroid;

  /// 默认 VTT 拉取的 wall-clock 硬上限。超过即视为服务器卡死，
  /// 缩略图轨道静默关闭（失败开放——视频继续播放）。
  ///
  /// 仅对**默认** [ThumbnailFetcher] 生效。如果调用方通过
  /// [NiumaPlayerController.thumbnailFetcher] 注入了自家 fetcher，
  /// 由其自行管理 timeout 策略。
  final Duration thumbnailFetchTimeout;

  /// VTT body 大小硬上限（字节）。默认 fetcher 流式读取响应，一旦
  /// 累计超过该值立即中止——恶意服务器无法强迫 VM 先把整个 body
  /// buffer 完再被拒绝。
  ///
  /// 5MB 已意味着上万条 cue；典型 thumbnail VTT 只有几 KB。仅对
  /// 默认 [ThumbnailFetcher] 生效。
  final int thumbnailMaxBodyBytes;
}

/// 用户直接交互的公共 controller。
///
/// 选择规则：
///   - iOS / Web → `package:video_player`（AVPlayer / `<video>` + hls.js）
///   - Android   → niuma_player 自家 native 插件
///
/// Android 上 native 插件会基于持久化的 `DeviceMemoryStore` 在
/// ExoPlayer 与 IJK 之间选择。若 ExoPlayer 在 opening 期间失败，
/// native 侧持久化地把该设备记成 "needs IJK"，本 controller 会透明
/// 地用 `forceIjk=true` 再试一次——用户只会看到短暂的延迟。
///
/// 通过 [NiumaMediaSource] 支持多线路播放（CDN failover、画质变体）。
/// 单 URL 场景建议用 [NiumaPlayerController.dataSource] 便捷 factory。
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
        _thumbnailFetcher = thumbnailFetcher ??
            _makeDefaultThumbnailFetcher(options ?? const NiumaPlayerOptions()),
        _thumbnailLoadState = source.thumbnailVtt == null
            ? ThumbnailLoadState.none
            : ThumbnailLoadState.idle,
        super(NiumaPlayerValue.uninitialized());

  /// 单 source 便捷 factory。把 [ds] 包成 [NiumaMediaSource.single]，
  /// 让无需多线路的调用方继续用更简洁的写法。
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

  /// 描述本 controller 所有可用播放线路的 [NiumaMediaSource]。
  /// 单 URL 播放传 [NiumaMediaSource.single]；画质 / CDN 切换传
  /// [NiumaMediaSource.lines]。
  final NiumaMediaSource source;

  /// 可选的 middleware 流水线，在每次 backend 起飞前作用于数据源。
  /// 在每次 `initialize`、每次 `switchLine`（Task 25）、每次重试
  /// （Task 26）上都会跑——保证 headers / signed URL 是新鲜的。
  final List<SourceMiddleware> middlewares;

  /// [initialize] 抛出可恢复错误（默认 network / transient）时套用的
  /// 重试策略。上限是策略的 [RetryPolicy.maxAttempts]；全部失败后错误
  /// 继续向上传播，触发现有的 Android forceIjk Try-Fail-Remember 兜底。
  ///
  /// **权衡**：重试运行在 forceIjk 兜底层*之内*。最坏情况下，单次面向
  /// 用户的 [initialize] 调用最多会做 `maxAttempts × 2` 次后端初始化
  /// 尝试——先 `maxAttempts` 次 ExoPlayer，再 `maxAttempts` 次 IJK。
  ///
  /// 一个永不完成的 initialize 的最差 wall-clock 预算：
  /// `maxAttempts × initTimeout × 2 + sum(backoff) × 2`。默认值下
  /// （`initTimeout: 30s`、`maxAttempts: 3`、指数退避 1s + 2s + 4s = 7s），
  /// 大约 `(3 × 30 + 7) × 2 ≈ 194s` 才会暴露失败。要收紧上限，
  /// 降低 [RetryPolicy.maxAttempts]、降低
  /// [NiumaPlayerOptions.initTimeout]，或传入 [RetryPolicy.none] 用
  /// 韧性换延迟。
  final RetryPolicy retryPolicy;

  /// 给只用一条线路的调用方的向后兼容访问器。
  /// 返回当前激活线路的数据源。
  NiumaDataSource get dataSource => source.currentLine.source;
  final NiumaPlayerOptions options;

  final PlatformBridge _platform;
  final BackendFactory _backendFactory;

  PlayerBackend? _backend;
  StreamSubscription<NiumaPlayerValue>? _valueSub;
  StreamSubscription<NiumaPlayerEvent>? _eventSub;
  Completer<void>? _initCompleter;
  bool _disposed = false;

  /// 跟踪当前激活线路的 id，以便 [switchLine] 能发出正确的
  /// [LineSwitching.fromId]。在 [switchLine] 成功时更新。
  String? _activeLineId;

  /// 经过 [middlewares] 流水线后的数据源。
  /// 由 [_runInitialize] 起始处填充，[_initNative] 复用。
  NiumaDataSource? _resolvedSource;

  // ----- Thumbnail (M8) -----
  final ThumbnailCache _thumbnailCache = ThumbnailCache();
  List<WebVttCue> _thumbnailCues = const <WebVttCue>[];
  String? _resolvedThumbnailUrl;
  final ThumbnailFetcher _thumbnailFetcher;
  ThumbnailLoadState _thumbnailLoadState;

  /// 进行中的加载 future——用于去重并发 [_loadThumbnailsIfAny] 调用，
  /// 让多次 `unawaited(...)` 触发也只做一次 fetch。
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

  /// [BackendSelected] / [FallbackTriggered] 等事件的 broadcast stream。
  /// 在 [initialize] 之前订阅是安全的。
  Stream<NiumaPlayerEvent> get events => _eventController.stream;

  /// 当前激活的 Dart 侧 backend。[initialize] 完成之前默认为
  /// `videoPlayer`（任意值——调用方应等 `BackendSelected`）。
  PlayerBackendKind get activeBackend =>
      _backend?.kind ?? PlayerBackendKind.videoPlayer;

  /// 当前激活 backend 的 texture id；video_player 不暴露 texture
  /// （它管理自己的 widget），返回 null。
  int? get textureId => _backend?.textureId;

  /// 底层 backend 实例。对外暴露以便 [NiumaPlayerView] 选择正确的
  /// 渲染 widget。
  PlayerBackend? get backend => _backend;

  /// 驱动平台特定的选择，并在 [backend] 上留下结果。
  /// 多次调用是安全的；后续调用返回同一个 future。
  ///
  /// 错误通过缓存 completer 的 future 传播，而非 rethrow：缓存的 future
  /// 是*唯一*订阅者，这里 `rethrow` 反而会让错误以 unhandled 形式冒出
  /// 来——因为 completer 的 future 永远不会再获得第二个订阅者。
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

  /// 把异常分类成 [PlayerErrorCategory] 以便决定是否重试。
  ///
  /// [TimeoutException] 映射到 [PlayerErrorCategory.network]。带有类型为
  /// [PlayerErrorCategory] 的 `.category` getter 的对象（例如测试 helper
  /// `_RetryableError`）通过 duck-typing 用该 getter 分类，因此测试类
  /// 永远不必在生产代码中可见。
  PlayerErrorCategory _categorize(Object e) {
    if (e is TimeoutException) return PlayerErrorCategory.network;
    try {
      final dynamic d = e;
      final c = d.category;
      if (c is PlayerErrorCategory) return c;
    } catch (_) {
      // 不是带分类的异常；继续往下走
    }
    return PlayerErrorCategory.unknown;
  }

  /// 按 [retryPolicy] 带重试地运行 [bringUp]。
  ///
  /// 每次抛错时用 [_categorize] 分类，并询问 [retryPolicy] 是否重试。
  /// 否则立即 rethrow，让调用方的错误处理路径（如 forceIjk 兜底）接管。
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
      await _withRetry(() async {
        // 每次重试：dispose 之前（已失败的）backend，重新跑 middleware
        // 流水线（重算 signed URL / 新鲜 headers），构造新 backend，
        // 再调用 initialize()。
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

    // Android：单一 native backend。下面的 Dart 侧重试逻辑就是
    // Try-Fail-Remember 机制的全部——native 自行挑选初始变体并持久化
    // "needs IJK"，所以这里要做的只是：第一次出于任何非终结原因失败
    // 时，dispose 之后用 `forceIjk=true` 重开。
    if (options.forceIjkOnAndroid) {
      await _initNative(forceIjk: true);
      unawaited(_loadThumbnailsIfAny());
      return;
    }

    try {
      await _initNative(forceIjk: false);
    } catch (e) {
      // 第一次尝试失败。如果原因是 codec 问题，native 应该已经写入
      // memory；不管怎样，我们用 forceIjk 重试，确保只要 IJK 能处理，
      // 用户就能看到*点儿什么*。
      _emit(FallbackTriggered(
        FallbackReason.error,
        errorCode: e.toString(),
      ));
      await _disposeCurrentBackend();
      await _initNative(forceIjk: true);
    }
    unawaited(_loadThumbnailsIfAny());
  }

  /// 在后台加载并解析可选的 [NiumaMediaSource.thumbnailVtt]。失败会被
  /// swallow（通过 [debugPrint] 打日志），保证视频播放永远不受坏掉
  /// 的缩略图轨道影响。
  ///
  /// 单次加载内幂等：并发调用共享同一个进行中的 future（I6）。完成后
  /// 缓存的 future 被清空（`whenComplete`），未来再调一次（例如外部
  /// 重试）就能真正重新发起 fetch（R2-I1）。目前 controller 自身不会
  /// 主动触发重新加载，但门已经打开（dartdoc 不再骗人说会重置）。
  Future<void> _loadThumbnailsIfAny() {
    if (_thumbnailLoadFuture != null) return _thumbnailLoadFuture!;
    final future = _runThumbnailLoad().whenComplete(() {
      _thumbnailLoadFuture = null;
    });
    _thumbnailLoadFuture = future;
    return future;
  }

  Future<void> _runThumbnailLoad() async {
    // R2-S4：防御性入口闸。镜像本方法内每个 await 后的 `_disposed` 守卫
    // （I5/I9），保证排在 dispose() 之后的加载根本不会把状态翻成 loading。
    if (_disposed) return;
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
      // I5：进 catch 前先检查 _disposed——dispose 中途完成的 fetcher
      // 不应该再去写已 dispose 的字段。
      if (_disposed) return;
      debugPrint('[niuma_player] thumbnail VTT 加载失败：$e（不影响播放）');
      // I9：同时清空两个状态字段，避免 partial state（cues 空但 resolvedUrl 有值）。
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
        // 每次重试：dispose 之前（已失败的）backend，重新跑 middleware
        // 流水线（重算 signed URL / 新鲜 headers），构造新 native backend，
        // 再调用 initialize()。
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
      // 把 wall-clock timeout 转成公共 events 流期望的 FallbackTriggered
      // 语义，再 rethrow 让调用方的重试路径继续跑。
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
      // `FallbackTriggered` 是 controller 级事件：controller 在
      // [_runInitialize] 内自己发出权威版本，所以这里把 backend 级
      // fallback 信号丢掉避免重复。
      if (e is FallbackTriggered) return;
      if (e is PipModeChanged) {
        value = value.copyWith(isInPictureInPicture: e.isInPip);
        // 退出 PiP（X 按钮 / restore 回 app / 系统自动关）默认暂停播放——
        // 与 B 站 / YouTube mobile 行为一致。业务想"退出 PiP 后继续放"
        // 自己监听 controller.events 拦 PipModeChanged(isInPip:false) 调
        // play() 即可。
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

  /// 切换到 [lineId] 标识的线路。
  ///
  /// 保存当前播放 position 和 `isPlaying` 状态，拆掉当前 backend，
  /// 在新线路 source 上跑 middleware 流水线，为目标线路拉起新 backend，
  /// seek 回保存的位置（非 0 时），切换前在播放则恢复播放。
  ///
  /// 成功时按顺序发出的事件：
  ///   1. [LineSwitching] — backend 拆除即将开始。
  ///   2. [LineSwitched]  — 新 backend 已就绪。
  ///
  /// 失败时发出 [LineSwitchFailed] 并 rethrow 错误。
  ///
  /// 当 [lineId] 不在 [source] 的 lines 中时抛 [ArgumentError]。
  /// 当 [lineId] 等于当前激活线路时静默 no-op。
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
          // 刚 attach 的 backend 不能泄漏；返回前先拆掉。
          await _disposeCurrentBackend();
          return;
        }
        await _withRetry(
            () => _backend!.initialize().timeout(options.initTimeout));
      } else {
        await _initNative(forceIjk: options.forceIjkOnAndroid);
      }
      if (_disposed) {
        // backend 已达到 "initialized"，但 controller 中途被 dispose
        // 了——清理后退出，不再发 LineSwitched。
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

  /// 清掉所有设备指纹下的 "this device needs IJK" 记忆。
  /// app 级"清缓存 / 重置"流程应调用此方法，让下次 initialize 重新
  /// 探测 ExoPlayer，而不是直接走 IJK。
  static Future<void> clearDeviceMemory() => DeviceMemory().clear();

  // ────────────── M12 PiP（画中画） ──────────────

  bool _autoEnterPip = false;
  PipLifecycleObserver? _pipObserver;

  /// 配置 app 切后台时是否自动进 PiP（默认 false）。
  ///
  /// **触发条件**（Task 6 实现）：app 进入 inactive + 当前 phase=playing
  /// + 不在 PiP 中。其他 phase（paused / buffering / idle / error / ended）
  /// 不会触发。
  bool get autoEnterPictureInPictureOnBackground => _autoEnterPip;

  /// 设置 [autoEnterPictureInPictureOnBackground]。
  /// 同值短路；不同值时（Task 6）注册 / 注销 [WidgetsBindingObserver]。
  set autoEnterPictureInPictureOnBackground(bool nextValue) {
    if (_autoEnterPip == nextValue) return;
    _autoEnterPip = nextValue;
    if (nextValue) {
      _pipObserver = PipLifecycleObserver(
        shouldEnter: () =>
            _autoEnterPip &&
            value.phase == PlayerPhase.playing &&
            !value.isInPictureInPicture,
        enter: enterPictureInPicture,
      );
      WidgetsBinding.instance.addObserver(_pipObserver!);
    } else if (_pipObserver != null) {
      WidgetsBinding.instance.removeObserver(_pipObserver!);
      _pipObserver = null;
    }
  }

  /// 进入 PiP。返回 true 表示 SDK 已发起请求；不保证用户允许（系统层可能拒绝）。
  ///
  /// 设备不支持 / video 未 initialize / 已在 PiP → 返回 false 不抛。
  /// 状态实际变更由原生 EventChannel 推送（参见 Task 11）。
  Future<bool> enterPictureInPicture() async {
    final v = value;
    if (!v.initialized) return false;
    if (v.isInPictureInPicture) return false;
    final backend = _backend;
    if (backend == null) return false;
    final aspect = _aspectInts(v.size);
    return backend.enterPictureInPicture(
      aspectNum: aspect.$1,
      aspectDen: aspect.$2,
    );
  }

  /// 退出 PiP。不在 PiP 是 no-op，返回 false。
  Future<bool> exitPictureInPicture() async {
    if (!value.isInPictureInPicture) return false;
    final backend = _backend;
    if (backend == null) return false;
    return backend.exitPictureInPicture();
  }

  /// 计算 aspect 整数 (num, den)。fallback 16:9。
  ///
  /// 算法：×1000 整数化 + GCD 约分。
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
    if (_pipObserver != null) {
      WidgetsBinding.instance.removeObserver(_pipObserver!);
      _pipObserver = null;
    }
    await _disposeCurrentBackend();
    await _eventController.close();
    _thumbnailCache.clear();
    super.dispose();
  }
}
