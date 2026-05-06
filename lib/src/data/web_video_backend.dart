import 'dart:async';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
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
    // 包 wrapper div：HtmlElementView 的 wrapper 也会拦 pointer events，
    // 单设 video 元素 pointer-events: none 不够——整树都设让事件穿透到
    // Flutter 上层 GestureDetector。
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
  }

  void _attachListeners() {
    _subs.add(_video.onLoadedMetadata.listen((_) => _maybeMarkInitialized()));
    _subs.add(_video.onDurationChange.listen((_) => _maybeMarkInitialized()));
    _subs.add(_video.onCanPlay.listen((_) => _maybeMarkInitialized()));
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
    }));
    _subs.add(_video.onTimeUpdate.listen((_) {
      if (_disposed) return;
      _emit(_value.copyWith(
        position: Duration(
          milliseconds: (_video.currentTime * 1000).round(),
        ),
      ));
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
      _setPhase(
        PlayerPhase.error,
        error: PlayerError(
          category: cat,
          message: msg,
          code: code?.toString(),
        ),
      );
    }));

    // 监听共享 PiP event bus（web 上没真正 PiP plugin，但保持 API
    // 一致——other backends 的 PiP 事件不会泄漏到 web，这条 sub 在 web
    // 上等于 inert）。
    _pipEventSub = pipEventBus().listen((_) {});
  }

  @override
  Future<void> initialize() async {
    if (_disposed) return;
    // browser 接到 src 后异步加载 metadata——直接返回，事件通过 listener 推
    _video.load();
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    try {
      await _video.play();
    } catch (e) {
      if (kDebugMode) debugPrint('[WebVideoBackend] play() rejected: $e');
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
    _video.volume = volume.clamp(0.0, 1.0);
  }

  @override
  Future<void> setLooping(bool looping) async {
    if (_disposed) return;
    _video.loop = looping;
  }

  @override
  Future<bool> enterNativeFullscreen() async {
    if (_disposed) return false;
    // iOS Safari 优先：webkitEnterFullscreen 是私有 API（进入原生 video
    // player UI），dart:html 不直接暴露，js_util.callMethod 反射调。
    // iOS Safari 上调 standard requestFullscreen 会静默失败。
    try {
      if (js_util.hasProperty(_video, 'webkitEnterFullscreen')) {
        js_util.callMethod(_video, 'webkitEnterFullscreen', []);
        return true;
      }
    } catch (_) {/* fallback 到标准 */}
    // 标准 Element.requestFullscreen——桌面 Chrome / Firefox / Edge / 桌面
    // Safari / Android Chrome 都支持 on video element。
    try {
      await _video.requestFullscreen();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> exitNativeFullscreen() async {
    if (_disposed) return false;
    // iOS Safari：webkitExitFullscreen on video
    try {
      if (js_util.hasProperty(_video, 'webkitExitFullscreen')) {
        js_util.callMethod(_video, 'webkitExitFullscreen', []);
        return true;
      }
    } catch (_) {/* fallback to document */}
    try {
      if (html.document.fullscreenElement != null) {
        html.document.exitFullscreen();
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
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
  }
}
