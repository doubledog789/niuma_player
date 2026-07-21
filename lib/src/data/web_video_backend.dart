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

/// 自家 web 后端：每实例独立 `<video>` element + `ui_web` platformViewRegistry，
/// 不依赖 `package:video_player` 的 web 实现——绕开其单全局 `<video>`、
/// 手势被拦、全屏搬迁黑屏等限制。web 平台无 PiP 强制 / 投屏 / 亮度音量 API。
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
    // HLS 判定不能用 canPlayType（部分 Chromium 返 "maybe" 却解不了）——
    // 用 navigator.vendor 区分 Apple WebKit（原生 HLS）更可靠。
    _useHlsJs = isHlsUrl(_dataSource.uri) && !_isAppleWebKit() && _hasMse();
    if (!_useHlsJs) {
      _video.src = _dataSource.uri;
    }
    // iOS Safari：无 playsinline 首次 play 会自动进系统全屏 player。
    _video.setAttribute('playsinline', 'true');
    _video.setAttribute('webkit-playsinline', 'true');
    // wrapper 也会拦 pointer events，整树设 none 让事件穿透到 Flutter 手势层。
    // 已知限制：<flt-platform-view> 容器仍会吞视频像素区的 tap。
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

  /// 每个 backend 实例分配唯一 viewType。
  static int _nextId = 0;

  /// 当前数据源；[load] 换源时更新，`<video>` 元素复用不重建。
  NiumaDataSource _dataSource;
  final String _viewType;
  late final web.HTMLVideoElement _video;
  late final web.HTMLDivElement _wrapper;

  /// 当前源是否需要 hls.js。
  bool _useHlsJs = false;

  /// hls.js 实例（JS `Hls` object）。
  JSObject? _hls;

  bool _disposed = false;
  bool _initialized = false;

  /// 播放意图：DOM reparent 导致浏览器自发暂停时据此自动续播。
  bool _intendedPlaying = false;

  /// iOS Safari 系统全屏 player 期间为 true——期间不做暂停自愈。
  bool _inNativeFullscreen = false;

  /// Rapid seek 合并（latest-wins），防反复 seek 卡死 hls.js SourceBuffer。
  bool _isSeeking = false;
  Duration? _pendingSeek;
  Timer? _seekSafetyTimer;

  /// [initialize] 等待的 completer——让上层立刻得知 load 成败，不等 initTimeout。
  Completer<void>? _initCompleter;

  /// Web overlay 假全屏状态；NiumaPlayerView 据此在 inline / overlay
  /// 间搬迁同一 element（单 element 只 mount 一处）。
  final ValueNotifier<bool> _isWebFullscreen = ValueNotifier<bool>(false);
  @override
  ValueListenable<bool> get webFullscreenState => _isWebFullscreen;

  NiumaPlayerValue _value = NiumaPlayerValue.uninitialized();
  final StreamController<NiumaPlayerValue> _valueController =
      StreamController<NiumaPlayerValue>.broadcast();
  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast();

  // 保存 removeEventListener 回调，dispose 时统一移除。
  final List<void Function()> _listenerRemovers = <void Function()>[];
  StreamSubscription<dynamic>? _pipEventSub;

  /// 注册 video 事件 listener 并登记反注册回调。
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

  /// duration 就绪即认为 init 完成，once-only。
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

  /// 重读 videoWidth/Height 同步 value.size——iOS Safari 首帧渲染前
  /// 尺寸可能为 0，需在 playing / timeupdate 上重试。
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
      // ended 后也会触发 pause，避免覆盖 ended phase。
      if (_value.phase == PlayerPhase.ended) return;
      // DOM reparent（全屏搬迁）会让浏览器自发暂停：意图仍在播、
      // 非系统全屏且页面可见时自动续播，不对外 emit paused。
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
      _maybeUpdateSize();
    });
    _on('seeked', () {
      if (_disposed) return;
      _seekSafetyTimer?.cancel();
      _isSeeking = false;
      final next = _pendingSeek;
      _pendingSeek = null;
      if (next != null) {
        // 还有排队目标 → 立刻 fire 最新值（latest-wins）。
        seekTo(next);
        return;
      }
      // Safari + hls.js：seek 到已 buffered 区间只发 'seeked' 不发
      // 'playing'，phase 会卡 buffering，在此按 video 真值兜底校准。
      if (_value.phase == PlayerPhase.buffering) {
        if (_video.paused) {
          _setPhase(PlayerPhase.paused);
        } else if (_video.readyState >= 3) {
          // HAVE_FUTURE_DATA
          _setPhase(PlayerPhase.playing);
        }
      }
    });
    _on('timeupdate', () {
      if (_disposed) return;
      _emit(_value.copyWith(
        position: Duration(
          milliseconds: (_video.currentTime * 1000).round(),
        ),
      ));
      if (_value.size.width <= 0 || _value.size.height <= 0) {
        _maybeUpdateSize();
      }
    });
    // buffered 进度随 timeupdate 更新（progress event 暴露不一致）。
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
      // 让 await initialize() 立刻拿到错误，不等 initTimeout。
      final c = _initCompleter;
      if (c != null && !c.isCompleted) {
        c.completeError(err);
      }
    });

    // 共享 PiP event bus 在 web 上 inert，仅保持 API 一致。
    _pipEventSub = pipEventBus().listen((_) {});
  }

  @override
  Future<void> initialize() async {
    if (_disposed) return;
    final completer = Completer<void>();
    _initCompleter = completer;
    if (_useHlsJs) {
      await _initHlsJs();
    } else {
      _video.load();
    }
    return completer.future;
  }

  @override
  bool get supportsSourceSwap => true;

  @override
  Future<void> load(NiumaDataSource source) async {
    if (_disposed) return;
    // 复用同一 <video> 元素与 platform-view，保住 iOS Safari 的
    // 「有声播放激活」（新建元素会丢激活、自动播被静音）。
    _intendedPlaying = false;
    _initialized = false;
    // 换源作废旧 seek 上下文，避免锁跨源残留吞掉新 seek。
    _seekSafetyTimer?.cancel();
    _seekSafetyTimer = null;
    _isSeeking = false;
    _pendingSeek = null;
    if (_hls != null) {
      _hls!.callMethod('destroy'.toJS);
      _hls = null;
    }
    _dataSource = source;
    final headers = source.headers ?? const <String, String>{};
    _video.crossOrigin = headers.isNotEmpty ? 'anonymous' : null;
    _useHlsJs = isHlsUrl(source.uri) && !_isAppleWebKit() && _hasMse();
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

  /// 加载 hls.js → 检查 MSE → attachMedia + loadSource；失败走 [_failInit]。
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
    // 只映射 fatal error；非 fatal 交给 hls.js 自愈，fatal 上抛给
    // orchestration 层 failover，backend 内不自己 retry。
    hls.callMethod('on'.toJS, 'hlsError'.toJS, _onHlsError.toJS);
    hls.callMethod('attachMedia'.toJS, _video as JSObject);
    hls.callMethod('loadSource'.toJS, _dataSource.uri.toJS);
  }

  /// 浏览器禁止 JS 设置的 forbidden request headers，设置会抛异常。
  static const Set<String> _forbiddenRequestHeaders = <String>{
    'accept-charset', 'accept-encoding', 'access-control-request-headers',
    'access-control-request-method', 'connection', 'content-length', 'cookie',
    'cookie2', 'date', 'dnt', 'expect', 'host', 'keep-alive', 'origin',
    'referer', 'te', 'trailer', 'transfer-encoding', 'upgrade', 'user-agent',
    'via',
  };

  /// 把安全请求头经 xhrSetup 带上，跳过 forbidden headers——referer /
  /// cookie 这类在 web 上无法用 JS 设置，鉴权请改用 token 或 URL 签名。
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

  /// 错误同步进 phase，并让仍在 await 的 [initialize] 立刻失败。
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
      // NotSupportedError = 源不可播 → 翻 error 并 rethrow 走 failover；
      // NotAllowedError / AbortError 是 autoplay 限制 / pause 抢断，静默吞。
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
    // 已有 seek 在路上 → 只更新目标，等 'seeked' 后 fire 最新值。
    if (_isSeeking) {
      _pendingSeek = position;
      return;
    }
    _isSeeking = true;
    _video.currentTime = position.inMilliseconds / 1000.0;
    // 兜底：极端 case 下 'seeked' 可能不触发，3s 后强制 release。
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
    // iOS Safari 的 volume setter 被静默忽略，只能靠 muted 让静音真正生效。
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
    // iOS Safari 不支持 requestFullscreen，只能 webkitEnterFullscreen
    // 进系统 player；其余浏览器走标准 API。
    try {
      final v = _video as JSObject;
      if (v.has('webkitEnterFullscreen')) {
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

  /// 退出 iOS 系统 player 后按需恢复播放——iOS 退出时默认会把 video 暂停。
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
    // 让仍挂着的 initialize future 立刻失败。
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
    // hls.js 持有 MSE buffer / xhr，必须显式 destroy，否则泄漏。
    _hls?.callMethod('destroy'.toJS);
    _hls = null;
    // 清 src 让浏览器释放底层资源。
    _video.src = '';
    _video.load();
    await _valueController.close();
    await _eventController.close();
    _isWebFullscreen.dispose();
  }
}

/// 进程级缓存：hls.js 脚本只注入一次，多实例共享。
Future<void>? _hlsLoadFuture;

/// 懒注入 vendored hls.js；幂等，失败不缓存可重试。
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

/// Safari / iOS WebKit（含 iOS Chrome）原生支持 HLS，无需 hls.js。
bool _isAppleWebKit() {
  final nav = globalContext.getProperty('navigator'.toJS) as JSObject?;
  final vendor = nav?.getProperty('vendor'.toJS) as JSString?;
  return vendor?.toDart == 'Apple Computer, Inc.';
}

/// 浏览器是否有 MSE——iPhone Safari 到 iOS 17.1+ 才有 ManagedMediaSource。
bool _hasMse() =>
    globalContext.has('MediaSource') || globalContext.has('ManagedMediaSource');
