import 'dart:async';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show Size;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';

import 'package:niuma_player/src/data/_pip_event_bus.dart';
import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_backend.dart';
import 'package:niuma_player/src/domain/player_state.dart';

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
class WebVideoBackend extends PlayerBackend {
  WebVideoBackend(this._dataSource)
      : _viewType = 'niuma-video-${_nextId++}' {
    final headers = _dataSource.headers ?? const <String, String>{};
    _video = html.VideoElement()
      ..src = _dataSource.uri
      ..autoplay = false
      ..controls = false
      ..crossOrigin = headers.isNotEmpty ? 'anonymous' : null
      ..style.pointerEvents = 'none'
      ..style.objectFit = 'contain'
      ..style.width = '100%'
      ..style.height = '100%';
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
    _wrapper = html.DivElement()
      ..style.pointerEvents = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..append(_video);
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _wrapper,
    );
    _attachListeners();
  }

  /// 进程级单调递增计数——每个 backend 实例分配唯一 viewType，避免
  /// HtmlElementView 在多 player 场景下复用同一 factory。
  static int _nextId = 0;

  final NiumaDataSource _dataSource;
  final String _viewType;
  late final html.VideoElement _video;
  late final html.DivElement _wrapper;

  bool _disposed = false;
  bool _initialized = false;

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

  // 监听 video element 各种事件——event listener 持有引用方便 dispose 时移除。
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];
  StreamSubscription<dynamic>? _pipEventSub;

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

  void _setPhase(PlayerPhase phase, {PlayerError? error, bool clearError = false}) {
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
    _subs.add(_video.onLoadedMetadata.listen((_) {
      _maybeMarkInitialized();
      _maybeUpdateSize();
    }));
    _subs.add(_video.onDurationChange.listen((_) => _maybeMarkInitialized()));
    _subs.add(_video.onCanPlay.listen((_) {
      _maybeMarkInitialized();
      _maybeUpdateSize();
    }));
    _subs.add(_video.onPlay.listen((_) {
      if (_disposed) return;
      _setPhase(PlayerPhase.playing);
    }));
    _subs.add(_video.onPause.listen((_) {
      if (_disposed) return;
      // ended 状态下 pause 事件也会触发——避免覆盖 ended phase
      if (_value.phase == PlayerPhase.ended) return;
      _setPhase(PlayerPhase.paused);
    }));
    _subs.add(_video.onWaiting.listen((_) {
      if (_disposed) return;
      _setPhase(PlayerPhase.buffering);
    }));
    _subs.add(_video.onPlaying.listen((_) {
      if (_disposed) return;
      _setPhase(PlayerPhase.playing);
      // 首帧渲染后 iOS Safari 才把真实尺寸塞进 videoWidth/videoHeight，
      // 这时再 retry 一次同步到 value.size。
      _maybeUpdateSize();
    }));
    _subs.add(_video.onTimeUpdate.listen((_) {
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
    }));
    // buffered 进度跟随 timeupdate 一起更新（progress event dart:html 暴露
    // 不一致，timeupdate 频率够用）
    _subs.add(_video.onTimeUpdate.listen((_) {
      if (_disposed) return;
      final buf = _video.buffered;
      if (buf.length == 0) return;
      final end = buf.end(buf.length - 1);
      _emit(_value.copyWith(
        bufferedPosition: Duration(milliseconds: (end * 1000).round()),
      ));
    }));
    _subs.add(_video.onEnded.listen((_) {
      if (_disposed) return;
      // 如果设了 loop，浏览器自动 seek 0 + replay——不会触发 ended
      _setPhase(PlayerPhase.ended);
    }));
    _subs.add(_video.onError.listen((_) {
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
    }));

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
    // browser 接到 src 后异步加载 metadata——event listener 在
    // [_maybeMarkInitialized]（成功）/ onError（失败）里 complete completer，
    // 让 `await initialize()` 真正等到 load 结果。
    _video.load();
    return completer.future;
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    try {
      await _video.play();
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
    _video.pause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (_disposed) return;
    _video.currentTime = position.inMilliseconds / 1000.0;
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
  Future<bool> enterNativeFullscreen() async {
    if (_disposed) return false;
    if (_isWebFullscreen.value) return true;
    _isWebFullscreen.value = true;
    return true;
  }

  @override
  Future<bool> exitNativeFullscreen() async {
    if (_disposed) return false;
    if (!_isWebFullscreen.value) return false;
    _isWebFullscreen.value = false;
    return true;
  }

  /// 业务可选：进浏览器原生 video player fullscreen——iOS Safari 走
  /// webkitEnterFullscreen（系统 UI，**Flutter 控件不可见**），桌面 / Android
  /// 走标准 requestFullscreen。**绝大多数业务推荐用 enterNativeFullscreen
  /// 走 Flutter Overlay 假全屏路径保留控件**——本方法仅给"我就要原生 video
  /// player UI"的业务用。
  Future<bool> enterBrowserVideoFullscreen() async {
    if (_disposed) return false;
    try {
      final v = _video as JSObject;
      if (v.has('webkitEnterFullscreen')) {
        v.callMethod('webkitEnterFullscreen'.toJS);
        return true;
      }
    } catch (_) {/* fallback */}
    try {
      await _video.requestFullscreen();
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
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _pipEventSub?.cancel();
    _pipEventSub = null;
    _video.pause();
    // 清 src 让浏览器释放底层资源
    _video.src = '';
    _video.load();
    await _valueController.close();
    await _eventController.close();
    _isWebFullscreen.dispose();
  }
}
