import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show Size;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'package:niuma_player/src/data/_pip_event_bus.dart';
import 'package:niuma_player/src/data/hls_detect.dart';
import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_backend.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/niuma_sdk_assets.dart';

/// 自家 web 实现——直接用 `<video>` HTML element + `ui_web`
/// `platformViewRegistry` 注册 view factory，**不依赖 `package:video_player`
/// 的 web 实现**。
///
/// 解决 `video_player_web` 的几个已知限制：
/// - 进程全局只一个 `<video>` element（多 controller 互相覆盖）→ 这里
///   每个 backend 实例创建独立 element，可多实例
/// - `HtmlElementView` 拦 pointer events 让 Flutter GestureDetector 收
///   不到 tap → 这里把 element 的 `pointer-events: none` 设掉，让 Flutter
///   层 GestureDetector 正常拿到
/// - 全屏 push/pop 时 element 游离黑屏 → 每个 NiumaPlayerView 实例都通过
///   `HtmlElementView(viewType)` 重新 attach，不会孤立
///
/// 不支持的功能（web 平台限制）：
/// - PiP：浏览器有原生 `<video>` PiP 但需要用户手势触发，SDK 不强制
/// - 投屏：web 不支持 DLNA / AirPlay 程序化触发——仍可通过浏览器 cast 菜单
/// - 设置亮度 / 系统音量：浏览器无 API
///
/// 实现基于 `package:web` + `dart:js_interop`（不用已废弃的 `dart:html`），
/// 因此可随 `flutter build web --wasm` 一起编译。
class WebVideoBackend extends PlayerBackend {
  WebVideoBackend(this._dataSource) : _viewType = 'niuma-video-${_nextId++}' {
    final headers = _dataSource.headers ?? const <String, String>{};
    _video = web.document.createElement('video') as web.HTMLVideoElement
      ..autoplay = false
      ..controls = false
      ..crossOrigin = headers.isNotEmpty ? 'anonymous' : null;
    _video.style
      ..setProperty('pointer-events', 'none')
      ..setProperty('object-fit', 'contain')
      ..setProperty('width', '100%')
      ..setProperty('height', '100%');
    // HLS(.m3u8) 哪些浏览器需要 hls.js：
    // - Safari / iOS（含 iOS Chrome，底层都是 WebKit）：原生支持 HLS，
    //   走 <video>.src，不下 hls.js。
    // - Chrome / Firefox / Edge：原生不支持，需 hls.js（MSE）。
    //
    // **不能用 `canPlayType('application/vnd.apple.mpegurl')` 判定**——实测
    // 部分 Chromium 对该 MIME 返 "maybe" 却根本解不了（native demuxer 直接
    // DEMUXER_ERROR_COULD_NOT_PARSE）。用 navigator.vendor 区分 Apple WebKit
    // （原生 HLS）更可靠。
    _useHlsJs = isHlsUrl(_dataSource.uri) && !_isAppleWebKit() && _hasMse();
    if (!_useHlsJs) {
      _video.src = _dataSource.uri;
    }
    // iOS Safari 经典坑：<video> 默认第一次 play 时**自动**进入 fullscreen
    // player（非 inline）——即使没调 fullscreen API。必须显式 playsinline
    // 让 video 在 inline 容器内播放。
    // - `playsinline` 属性是 HTML5 标准，所有现代浏览器支持
    // - `webkit-playsinline` 兼容 iOS 9 及之前的旧 Safari
    _video.setAttribute('playsinline', 'true');
    _video.setAttribute('webkit-playsinline', 'true');
    // 包 wrapper div：HtmlElementView 的 wrapper 也会拦 pointer events，
    // 单设 video 元素 pointer-events: none 不够——整树都设让事件穿透到
    // Flutter 上层 GestureDetector。
    //
    // **已知限制**：`<flt-platform-view>` 容器自身仍是
    // `pointer-events: auto`，落在视频像素区的 tap 仍被容器吞掉，到不了
    // Flutter canvas 上的 GestureDetector——表现为短视频"单击视频区域
    // 不暂停"。曾经尝试用 MutationObserver 给容器同步设
    // `pointer-events: none`，但 iOS Safari + Flutter Web canvas 层级
    // 在 fullscreen overlay 场景下事件路由整体崩——所有按钮失灵 + 视频
    // 黑屏。已回退。Web 上"在视频外侧 tap"或"用底栏进度条 / 暂停按钮"
    // 是当前 workaround；后续如有更稳的事件穿透方案再启用。
    _wrapper = web.document.createElement('div') as web.HTMLDivElement;
    _wrapper.style
      ..setProperty('pointer-events', 'none')
      ..setProperty('width', '100%')
      ..setProperty('height', '100%');
    _wrapper.appendChild(_video);
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _wrapper,
    );
    _attachListeners();
  }

  /// 进程级单调递增计数——每个 backend 实例分配唯一 viewType，避免
  /// HtmlElementView 在多 player 场景下复用同一 factory。
  static int _nextId = 0;

  /// 当前数据源。换源（[load]）时更新——`<video>` 元素本身复用、不重建。
  NiumaDataSource _dataSource;
  final String _viewType;
  late final web.HTMLVideoElement _video;
  late final web.HTMLDivElement _wrapper;

  /// true 表示当前源需要 hls.js（HLS 源 + 浏览器原生不支持）。构造时算出，
  /// [load] 换源时重算。
  bool _useHlsJs = false;

  /// hls.js 实例（JS `Hls` object）——仅 [_useHlsJs] 时在 [initialize]
  /// 创建，[dispose] 销毁。
  JSObject? _hls;

  bool _disposed = false;
  bool _initialized = false;

  /// 用户 / 业务的播放意图：[play] 置 true、[pause] 置 false。video 被 DOM
  /// reparent（如 web 全屏搬迁）时浏览器会自发暂停它——此时若意图仍在播，
  /// pause 事件处理里自动续播，避免"全屏后 / 退出后卡停"。
  bool _intendedPlaying = false;

  /// iOS Safari `webkitEnterFullscreen` 系统 player 期间为 true。期间用户用系统
  /// UI 暂停也是 video pause 事件、且意图仍在播，但**不该被自愈顶回播放**——
  /// 自愈只服务 Chrome overlay 全屏的 reparent 自发暂停。webkitendfullscreen 复位。
  bool _inNativeFullscreen = false;

  /// Rapid seek 合并（latest-wins）：已有 seek 在路上时，新的 [seekTo] 只更新
  /// [_pendingSeek] 目标，待 `'seeked'` 事件后再 fire 最新值。防止反复 seek 把
  /// hls.js 的 `SourceBuffer` 卡进 `updating=true` 永不释放（`'playing'` 永不来）。
  bool _isSeeking = false;
  Duration? _pendingSeek;
  Timer? _seekSafetyTimer;

  /// [initialize] 等待的 completer——load 成功（onLoadedMetadata 等）
  /// complete()，load 失败（onError）completeError()。让上层 `await
  /// backend.initialize()` 能真正得知 load 结果，而不是 fire-and-forget
  /// 撞到 [NiumaPlayerOptions.initTimeout] 的 30s timeout 才知道失败。
  Completer<void>? _initCompleter;

  /// Web "Flutter Overlay 假全屏" 状态——业务用 [enterNativeFullscreen]
  /// 进入时翻 true。NiumaPlayerView 监听本字段切换渲染：fullscreen 时
  /// inline 位置返 SizedBox 把 video element 让给 overlay；overlay 那边
  /// 通过 InheritedWidget marker 强制渲染 video，HtmlElementView 重新
  /// attach 同一 wrapper element 到 overlay 容器——单 element 在 widget
  /// tree 中只 mount 一处，不冲突。
  final ValueNotifier<bool> _isWebFullscreen = ValueNotifier<bool>(false);
  @override
  ValueListenable<bool> get webFullscreenState => _isWebFullscreen;

  NiumaPlayerValue _value = NiumaPlayerValue.uninitialized();
  final StreamController<NiumaPlayerValue> _valueController =
      StreamController<NiumaPlayerValue>.broadcast();
  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast();

  // video element 事件监听——保存 removeEventListener 回调，dispose 时统一移除。
  final List<void Function()> _listenerRemovers = <void Function()>[];
  StreamSubscription<dynamic>? _pipEventSub;

  /// 注册一个 video element 事件 listener，并登记反注册回调。listener 体
  /// 都不关心 event 对象（一律读 `_video.xxx`），所以 handler 不带参。
  void _on(String type, void Function() handler) {
    final cb = ((web.Event _) => handler()).toJS;
    _video.addEventListener(type, cb);
    _listenerRemovers.add(() => _video.removeEventListener(type, cb));
  }

  @override
  PlayerBackendKind get kind => PlayerBackendKind.videoPlayer;

  @override
  int? get textureId => null;

  @override
  String? get htmlViewType => _viewType;

  @override
  NiumaPlayerValue get value => _value;

  @override
  Stream<NiumaPlayerValue> get valueStream => _valueController.stream;

  @override
  Stream<NiumaPlayerEvent> get eventStream => _eventController.stream;

  void _emit(NiumaPlayerValue v) {
    if (_disposed) return;
    _value = v;
    _valueController.add(v);
  }

  void _setPhase(PlayerPhase phase,
      {PlayerError? error, bool clearError = false}) {
    final next = _value.copyWith(
      phase: phase,
      error: error,
      clearError: clearError,
    );
    _emit(next);
  }

  /// video element 的 readyState >= HAVE_CURRENT_DATA 时认为已 init 完。
  void _maybeMarkInitialized() {
    if (_initialized || _disposed) return;
    final dur = _video.duration;
    final hasDuration = dur.isFinite && dur > 0;
    if (!hasDuration) return;
    _initialized = true;
    final w = _video.videoWidth;
    final h = _video.videoHeight;
    _emit(_value.copyWith(
      phase: _video.paused ? PlayerPhase.ready : PlayerPhase.playing,
      duration: Duration(milliseconds: (dur * 1000).round()),
      size: w > 0 && h > 0 ? Size(w.toDouble(), h.toDouble()) : Size.zero,
    ));
    final c = _initCompleter;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// 后续从 video element 重新读 videoWidth/videoHeight 同步到 value.size。
  ///
  /// **iOS Safari quirk**：onLoadedMetadata / onDurationChange / onCanPlay 这
  /// 几个事件 fire 时，`videoWidth` / `videoHeight` 可能仍然是 0——直到
  /// 第一帧实际渲染才填充真实尺寸。`_maybeMarkInitialized` 是 once-only
  /// 的，size=0 一旦写进 value 就再也不更新；上层"按视频比例选 fit"
  /// 的逻辑就永远拿 16:9 默认值。
  ///
  /// 解决：在 onPlaying（首帧渲染后必触发）+ onTimeUpdate（保险 polling）
  /// 上调本方法 retry 读 videoWidth/Height；非零且与现有不同时 emit
  /// 新 value——上层 ValueListenableBuilder 重 build，正确决策 fit。
  void _maybeUpdateSize() {
    if (_disposed) return;
    final w = _video.videoWidth;
    final h = _video.videoHeight;
    if (w <= 0 || h <= 0) return;
    final newSize = Size(w.toDouble(), h.toDouble());
    if (_value.size == newSize) return;
    _emit(_value.copyWith(size: newSize));
  }

  void _attachListeners() {
    _on('loadedmetadata', () {
      _maybeMarkInitialized();
      _maybeUpdateSize();
    });
    _on('durationchange', _maybeMarkInitialized);
    _on('canplay', () {
      _maybeMarkInitialized();
      _maybeUpdateSize();
    });
    _on('play', () {
      if (_disposed) return;
      _setPhase(PlayerPhase.playing);
    });
    _on('pause', () {
      if (_disposed) return;
      // ended 状态下 pause 事件也会触发——避免覆盖 ended phase
      if (_value.phase == PlayerPhase.ended) return;
      // video 被 DOM reparent（web 全屏搬迁等）时浏览器会自发暂停——若用户
      // 意图仍在播，自动续播、不对外 emit paused，避免"全屏后 / 退出后卡停"。
      // 用户主动 pause() 已把 _intendedPlaying 置 false，走下面正常 paused 分支。
      // 系统原生全屏（iOS Safari）期间也不自愈——见 _inNativeFullscreen 注释。
      // 页面隐藏（home / 切后台）时也不自愈——否则后台被浏览器暂停的 video 会被
      // 顶回播放；回前台由上层（feed lifecycle）续播。
      if (_intendedPlaying && !_inNativeFullscreen && !web.document.hidden) {
        unawaited(_video.play().toDart.then((_) {}, onError: (_) {}));
        return;
      }
      _setPhase(PlayerPhase.paused);
    });
    _on('waiting', () {
      if (_disposed) return;
      _setPhase(PlayerPhase.buffering);
    });
    _on('playing', () {
      if (_disposed) return;
      _setPhase(PlayerPhase.playing);
      // 首帧渲染后 iOS Safari 才把真实尺寸塞进 videoWidth/videoHeight，
      // 这时再 retry 一次同步到 value.size。
      _maybeUpdateSize();
    });
    _on('seeked', () {
      if (_disposed) return;
      _seekSafetyTimer?.cancel();
      _isSeeking = false;
      final next = _pendingSeek;
      _pendingSeek = null;
      if (next != null) {
        // 还有排队目标 → 立刻 fire 最新值（latest-wins coalescing）。
        seekTo(next);
        return;
      }
      // Safari + hls.js quirk：seek 到已 buffered 范围内时，<video> 只发 'seeked'，
      // 不发 'playing'/'waiting'（readyState 没掉过、video 没断过）→ phase 卡在上
      // 一次 seek 触发的 buffering。'seeked' 是 seek 完成必触发事件，在此按 video
      // 真值兜底校准 phase；仅当当前为 buffering 时纠正，playing/paused/ended/
      // error 等明确状态保持不动，避免误覆盖用户意图。
      if (_value.phase == PlayerPhase.buffering) {
        if (_video.paused) {
          _setPhase(PlayerPhase.paused);
        } else if (_video.readyState >= 3) {
          // HAVE_FUTURE_DATA：浏览器认为足够推进当前播放头。
          _setPhase(PlayerPhase.playing);
        }
        // readyState < 3 && !paused → 真的还在缓冲，phase 保持，等 'playing' 自然驱动。
      }
    });
    _on('timeupdate', () {
      if (_disposed) return;
      _emit(_value.copyWith(
        position: Duration(
          milliseconds: (_video.currentTime * 1000).round(),
        ),
      ));
      // size 还是 0 就再 try——onPlaying 也漏检的极端 case 兜底，size
      // 拿到后下次 timeUpdate 早期 return 不再触发。
      if (_value.size.width <= 0 || _value.size.height <= 0) {
        _maybeUpdateSize();
      }
    });
    // buffered 进度跟随 timeupdate 一起更新（progress event 暴露不一致，
    // timeupdate 频率够用）
    _on('timeupdate', () {
      if (_disposed) return;
      final buf = _video.buffered;
      if (buf.length == 0) return;
      final end = buf.end(buf.length - 1);
      _emit(_value.copyWith(
        bufferedPosition: Duration(milliseconds: (end * 1000).round()),
      ));
    });
    _on('ended', () {
      if (_disposed) return;
      // 如果设了 loop，浏览器自动 seek 0 + replay——不会触发 ended
      _setPhase(PlayerPhase.ended);
    });
    _on('error', () {
      if (_disposed) return;
      final code = _video.error?.code;
      final msg = _video.error?.message ?? 'unknown video error';
      PlayerErrorCategory cat;
      switch (code) {
        case 1: // MEDIA_ERR_ABORTED
        case 2: // MEDIA_ERR_NETWORK
          cat = PlayerErrorCategory.network;
          break;
        case 3: // MEDIA_ERR_DECODE
        case 4: // MEDIA_ERR_SRC_NOT_SUPPORTED
          cat = PlayerErrorCategory.codecUnsupported;
          break;
        default:
          cat = PlayerErrorCategory.unknown;
      }
      final err = PlayerError(
        category: cat,
        message: msg,
        code: code?.toString(),
      );
      _setPhase(
        PlayerPhase.error,
        error: err,
      );
      // initialize() 的 await 也要拿到错误——让上层 auto-failover /
      // rollback 路径立刻进入 try-catch，而不是等 30s initTimeout 撞墙。
      final c = _initCompleter;
      if (c != null && !c.isCompleted) {
        c.completeError(err);
      }
    });

    // 监听共享 PiP event bus（web 上没真正 PiP plugin，但保持 API
    // 一致——other backends 的 PiP 事件不会泄漏到 web，这条 sub 在 web
    // 上等于 inert）。
    _pipEventSub = pipEventBus().listen((_) {});
  }

  @override
  Future<void> initialize() async {
    if (_disposed) return;
    final completer = Completer<void>();
    _initCompleter = completer;
    if (_useHlsJs) {
      // hls.js 路径：异步加载脚本 + attachMedia 后，<video> 的标准 media
      // 事件（loadedmetadata / canplay）照常触发，completer 仍由
      // [_maybeMarkInitialized]（成功）/ hls.js fatal error（失败）完成。
      await _initHlsJs();
    } else {
      // browser 接到 src 后异步加载 metadata——event listener 在
      // [_maybeMarkInitialized]（成功）/ onError（失败）里 complete completer，
      // 让 `await initialize()` 真正等到 load 结果。
      _video.load();
    }
    return completer.future;
  }

  @override
  bool get supportsSourceSwap => true;

  @override
  Future<void> load(NiumaDataSource source) async {
    if (_disposed) return;
    // **复用同一个 <video> 元素与 platform-view**（关键：保住 iOS Safari 的
    // 「有声播放激活」——新建 video 元素会丢激活、滑动自动播又被静音），这里
    // 只换 src / hls 源。
    _intendedPlaying = false;
    _initialized = false;
    // 换源即作废旧 seek 上下文（避免锁跨源残留导致换源后第一次 seek 被吞）。
    _seekSafetyTimer?.cancel();
    _seekSafetyTimer = null;
    _isSeeking = false;
    _pendingSeek = null;
    // 清旧 hls 实例（持有 MSE buffer / xhr）。
    if (_hls != null) {
      _hls!.callMethod('destroy'.toJS);
      _hls = null;
    }
    _dataSource = source;
    final headers = source.headers ?? const <String, String>{};
    _video.crossOrigin = headers.isNotEmpty ? 'anonymous' : null;
    _useHlsJs = isHlsUrl(source.uri) && !_isAppleWebKit() && _hasMse();
    // 重置 value 到未初始化（position / duration / size 归零、清错误）。
    _value = NiumaPlayerValue.uninitialized();
    _emit(_value);
    final completer = Completer<void>();
    _initCompleter = completer;
    if (_useHlsJs) {
      await _initHlsJs();
    } else {
      _video.src = source.uri;
      _video.load();
    }
    return completer.future;
  }

  /// 加载 hls.js → 检查 MSE → `new Hls()` + attachMedia + loadSource。
  /// 脚本加载失败或浏览器无 MSE 时直接 [_failInit]。
  Future<void> _initHlsJs() async {
    try {
      await _ensureHlsJsLoaded();
    } catch (e) {
      _failInit(PlayerError(
        category: PlayerErrorCategory.network,
        message: 'hls.js failed to load: $e',
      ));
      return;
    }
    if (_disposed) return;
    final hlsCtor = globalContext.getProperty('Hls'.toJS) as JSFunction;
    final supported = (hlsCtor.getProperty('isSupported'.toJS) as JSFunction)
        .callAsFunction(hlsCtor) as JSBoolean?;
    if (supported?.toDart != true) {
      _failInit(PlayerError(
        category: PlayerErrorCategory.codecUnsupported,
        message: 'MSE (Media Source Extensions) not supported by this browser',
      ));
      return;
    }
    final hls = hlsCtor.callAsConstructor<JSObject>(_buildHlsConfig());
    _hls = hls;
    // 只处理 fatal error 映射进 PlayerError；非 fatal 交给 hls.js 自愈，
    // fatal 上抛后由 orchestration 层 auto-failover / 换线接管（与既有架构
    // 一致，backend 内不自己 retry）。'hlsError' === Hls.Events.ERROR。
    hls.callMethod('on'.toJS, 'hlsError'.toJS, _onHlsError.toJS);
    hls.callMethod('attachMedia'.toJS, _video as JSObject);
    hls.callMethod('loadSource'.toJS, _dataSource.uri.toJS);
  }

  /// 浏览器禁止 JS 通过 `setRequestHeader` 设置的 forbidden request headers——
  /// 设它们会抛 `Refused to set unsafe header`（并可能中断 HLS 加载）。这些由
  /// 浏览器自己管（如 referer 用页面 URL、user-agent 用浏览器标识）。
  static const Set<String> _forbiddenRequestHeaders = <String>{
    'accept-charset', 'accept-encoding', 'access-control-request-headers',
    'access-control-request-method', 'connection', 'content-length', 'cookie',
    'cookie2', 'date', 'dnt', 'expect', 'host', 'keep-alive', 'origin',
    'referer', 'te', 'trailer', 'transfer-encoding', 'upgrade', 'user-agent',
    'via',
  };

  /// 构造 hls.js 配置：把 [_dataSource.headers] 里**安全**的请求头通过 xhrSetup
  /// 带上（鉴权 token 等），但跳过浏览器 forbidden headers（referer/host/
  /// user-agent…）——否则 hls.js 设 referer 会抛 "Refused to set unsafe header"。
  ///
  /// **referer / cookie 这类在 web 上无法用 JS 设置**：referer 由浏览器按页面
  /// URL 自动带（可用 `<meta name="referrer">` / Referrer-Policy 调整策略，但不能
  /// 指定任意值）。鉴权请改用可放在普通 header 的 token，或 URL 签名。
  JSObject _buildHlsConfig() {
    final config = JSObject();
    final headers = _dataSource.headers;
    if (headers == null || headers.isEmpty) return config;
    config.setProperty(
      'xhrSetup'.toJS,
      ((JSObject xhr, JSString _) {
        headers.forEach((k, v) {
          if (_forbiddenRequestHeaders.contains(k.toLowerCase())) return;
          try {
            xhr.callMethod('setRequestHeader'.toJS, k.toJS, v.toJS);
          } catch (_) {/* 个别 header 仍被浏览器拒，忽略不中断加载 */}
        });
      }).toJS,
    );
    return config;
  }

  void _onHlsError(JSAny _, JSObject data) {
    if (_disposed) return;
    final fatal = data.getProperty<JSBoolean?>('fatal'.toJS)?.toDart ?? false;
    if (!fatal) return;
    final type = data.getProperty<JSString?>('type'.toJS)?.toDart;
    final details = data.getProperty<JSString?>('details'.toJS)?.toDart ??
        'hls.js fatal error';
    final category = switch (type) {
      'networkError' => PlayerErrorCategory.network,
      'mediaError' => PlayerErrorCategory.codecUnsupported,
      _ => PlayerErrorCategory.unknown,
    };
    _failInit(PlayerError(category: category, message: details, code: type));
  }

  /// 把错误同步进 phase，并让仍在 await 的 [initialize] 立刻拿到——不等
  /// 30s initTimeout 撞墙（与 [_attachListeners] 里 onError 同款语义）。
  void _failInit(PlayerError err) {
    _setPhase(PlayerPhase.error, error: err);
    final c = _initCompleter;
    if (c != null && !c.isCompleted) c.completeError(err);
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    _intendedPlaying = true;
    try {
      await _video.play().toDart;
    } catch (e) {
      if (kDebugMode) debugPrint('[WebVideoBackend] play() rejected: $e');
      // 区分 fatal vs 非 fatal：
      // - **NotSupportedError**：源不支持（无 codec / 404 / src 为空）→
      //   翻 PlayerPhase.error，业务侧 errorBuilder 渲错误 UI。
      //   throw 让上层 [switchLine] / [initialize] 的 try-catch 走 rollback /
      //   auto-failover 路径。
      // - **NotAllowedError / AbortError**：浏览器 autoplay 限制或 pause()
      //   抢断——这些不是真错误，silent 吞掉，让用户重试 / pause 走自己的
      //   流程。
      final s = e.toString();
      if (s.contains('NotSupportedError') ||
          s.contains('no supported source') ||
          s.contains('no supported sources')) {
        _setPhase(
          PlayerPhase.error,
          error: PlayerError(
            category: PlayerErrorCategory.codecUnsupported,
            message: s,
          ),
        );
        rethrow;
      }
    }
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    _intendedPlaying = false;
    _video.pause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (_disposed) return;
    // 已有 seek 在路上 → 只更新目标，等 'seeked' 后再 fire 最新值（latest-wins）。
    if (_isSeeking) {
      _pendingSeek = position;
      return;
    }
    _isSeeking = true;
    _video.currentTime = position.inMilliseconds / 1000.0;
    // 兜底：'seeked' 通常几百 ms 内触发，但 hls.js 卡死等极端 case 可能不触发。
    // 3s 没等到就强制 release，把排队 target 应用，保证 seek 不会永久停摆。
    _seekSafetyTimer?.cancel();
    _seekSafetyTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed) return;
      _isSeeking = false;
      final next = _pendingSeek;
      _pendingSeek = null;
      if (next != null) seekTo(next);
    });
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (_disposed) return;
    _video.playbackRate = speed;
    _emit(_value.copyWith(playbackSpeed: speed));
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    final clamped = volume.clamp(0.0, 1.0);
    _video.volume = clamped;
    // iOS Safari 把 `<video>.volume` setter 当**只读**——程序设的值被
    // 静默忽略，用户只能用硬件音量键调音量。但 `.muted` 是支持的。
    // 所以 setVolume(0) 必须同步翻 `.muted=true` 才能让"静音按钮"
    // 在 iOS Safari 上真正生效；解除静音同理回 false。
    _video.muted = clamped == 0.0;
  }

  @override
  Future<void> setLooping(bool looping) async {
    if (_disposed) return;
    _video.loop = looping;
  }

  @override
  Future<void> setWebNativeControls(bool show) async {
    if (_disposed) return;
    _video.controls = show;
  }

  @override
  Future<bool> enterNativeFullscreen() async {
    if (_disposed) return false;
    // 浏览器原生全屏：iOS Safari 不支持 Element.requestFullscreen()，只能走
    // <video>.webkitEnterFullscreen()（进 iOS 系统原生 video player UI——业务
    // 的 Flutter 控件不会跟着进全屏）；桌面 Safari / Chrome / Firefox /
    // Android Chrome 走标准 requestFullscreen()。
    try {
      final v = _video as JSObject;
      if (v.has('webkitEnterFullscreen')) {
        // iOS Safari：进系统 player 前记住播放态；退出（webkitendfullscreen）后
        // video 常被系统暂停，自动恢复播放，省得用户手动再点一次。
        final wasPlaying = !_video.paused;
        _inNativeFullscreen = true;
        _listenWebkitEndFullscreenOnce(resumePlay: wasPlaying);
        v.callMethod('webkitEnterFullscreen'.toJS);
        return true;
      }
    } catch (_) {/* 落到标准 API */}
    try {
      await _video.requestFullscreen().toDart;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// iOS Safari 专用：监听一次 `webkitendfullscreen`（退出系统 player），退出后
  /// 若进全屏前在播放则恢复播放——iOS 退出系统 player 默认会把 video 暂停。
  void _listenWebkitEndFullscreenOnce({required bool resumePlay}) {
    late final JSFunction cb;
    cb = ((web.Event _) {
      _video.removeEventListener('webkitendfullscreen', cb);
      _inNativeFullscreen = false;
      if (_disposed || !resumePlay) return;
      unawaited(play());
    }).toJS;
    _video.addEventListener('webkitendfullscreen', cb);
  }

  @override
  Future<bool> exitNativeFullscreen() async {
    if (_disposed) return false;
    // iOS Safari 的 webkitEnterFullscreen 进系统 player，用户在系统 UI 内自行
    // 退出（webkitExitFullscreen 尽力而为）；桌面 / Chrome 走
    // document.exitFullscreen()。
    try {
      final v = _video as JSObject;
      if (v.has('webkitExitFullscreen')) {
        v.callMethod('webkitExitFullscreen'.toJS);
        return true;
      }
    } catch (_) {/* 落到标准 API */}
    try {
      if (web.document.fullscreenElement != null) {
        await web.document.exitFullscreen().toDart;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // 还在 await initialize 的调用方要立刻拿到错误，不留挂着的 future。
    final c = _initCompleter;
    if (c != null && !c.isCompleted) {
      c.completeError(StateError('WebVideoBackend disposed before initialize'));
    }
    for (final remove in _listenerRemovers) {
      remove();
    }
    _listenerRemovers.clear();
    _seekSafetyTimer?.cancel();
    _seekSafetyTimer = null;
    await _pipEventSub?.cancel();
    _pipEventSub = null;
    _video.pause();
    // hls.js 持有 MSE buffer / xhr，必须显式 destroy 释放，否则泄漏。
    _hls?.callMethod('destroy'.toJS);
    _hls = null;
    // 清 src 让浏览器释放底层资源
    _video.src = '';
    _video.load();
    await _valueController.close();
    await _eventController.close();
    _isWebFullscreen.dispose();
  }
}

/// 进程级缓存：hls.js 脚本只注入一次，多个 [WebVideoBackend] 实例共享。
Future<void>? _hlsLoadFuture;

/// 懒注入 vendored hls.js `<script>`，await 到 load 完成。幂等：window.Hls
/// 已存在（消费方自己在 index.html 引了，或上次已注入）直接返回；加载失败
/// 不缓存失败 future，下次还能重试。
Future<void> _ensureHlsJsLoaded() {
  final existing = _hlsLoadFuture;
  if (existing != null) return existing;
  if (globalContext.has('Hls')) {
    return _hlsLoadFuture = Future<void>.value();
  }
  final completer = Completer<void>();
  final script = web.document.createElement('script') as web.HTMLScriptElement
    ..src = NiumaSdkAssets.hlsJsUrl
    ..type = 'text/javascript';
  late final JSFunction onLoad;
  late final JSFunction onError;
  void cleanup() {
    script.removeEventListener('load', onLoad);
    script.removeEventListener('error', onError);
  }

  onLoad = ((web.Event _) {
    if (!completer.isCompleted) completer.complete();
    cleanup();
  }).toJS;
  onError = ((web.Event _) {
    if (!completer.isCompleted) {
      _hlsLoadFuture = null;
      completer.completeError(
        StateError('failed to load hls.js from ${NiumaSdkAssets.hlsJsUrl}'),
      );
    }
    cleanup();
  }).toJS;
  script.addEventListener('load', onLoad);
  script.addEventListener('error', onError);
  web.document.head!.appendChild(script);
  return _hlsLoadFuture = completer.future;
}

/// navigator.vendor === 'Apple Computer, Inc.'——Safari / iOS WebKit（含
/// iOS Chrome）。这些浏览器原生支持 HLS，无需 hls.js。
bool _isAppleWebKit() {
  final nav = globalContext.getProperty('navigator'.toJS) as JSObject?;
  final vendor = nav?.getProperty('vendor'.toJS) as JSString?;
  return vendor?.toDart == 'Apple Computer, Inc.';
}

/// 浏览器是否有 MSE（hls.js 的硬性前提）。iPhone Safari 历史上无
/// `MediaSource`（iOS 17.1+ 才补 `ManagedMediaSource`），两者都查。
bool _hasMse() =>
    globalContext.has('MediaSource') || globalContext.has('ManagedMediaSource');
