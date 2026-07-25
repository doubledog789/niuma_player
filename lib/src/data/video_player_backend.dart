import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_backend.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/data/_pip_event_bus.dart';

/// 包装 `package:video_player` 的 [PlayerBackend] 实现。
class VideoPlayerBackend extends PlayerBackend {
  VideoPlayerBackend(this._dataSource, {this.useAndroidPlatformView = false});

  final NiumaDataSource _dataSource;

  /// Android 上映射为 vp 的 `VideoViewType.platformView`（SurfaceView，
  /// Hybrid Composition）——对齐 0.3.3 根治有声黑屏的渲染路径。
  final bool useAndroidPlatformView;

  late final VideoPlayerController _inner = _buildController();

  NiumaPlayerValue _value = NiumaPlayerValue.uninitialized();
  final StreamController<NiumaPlayerValue> _valueController =
      StreamController<NiumaPlayerValue>.broadcast();
  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast();

  bool _disposed = false;

  static const MethodChannel _systemChannel =
      MethodChannel('niuma_player/system');
  static const MethodChannel _pipChannel = MethodChannel('niuma_player/pip');

  StreamSubscription<dynamic>? _pipEventSub;

  /// 底层 controller。对外暴露以便 [NiumaPlayerView] 把它交给
  /// `package:video_player` 的 `VideoPlayer` widget。
  VideoPlayerController get innerController => _inner;

  late final VideoViewType _viewType = useAndroidPlatformView && Platform.isAndroid
      ? VideoViewType.platformView
      : VideoViewType.textureView;

  /// platformView 路径下底层 ExoPlayer 的输出 surface 是独占资源——同一
  /// player 同时只能绑一个 SurfaceView，所以同一时刻只允许一份渲染 widget
  /// 挂载（`NiumaPlayerView` 用 `ExclusiveSurfaceGate` 仲裁）。texture 路径
  /// 是纯消费者，多份可并存。
  bool get usesExclusiveSurface => _viewType == VideoViewType.platformView;

  VideoPlayerController _buildController() {
    final headers = _dataSource.headers ?? const <String, String>{};
    switch (_dataSource.type) {
      case NiumaSourceType.network:
        return VideoPlayerController.networkUrl(
          Uri.parse(_dataSource.uri),
          httpHeaders: headers,
          viewType: _viewType,
        );
      case NiumaSourceType.asset:
        return VideoPlayerController.asset(_dataSource.uri,
            viewType: _viewType);
      case NiumaSourceType.file:
        return VideoPlayerController.file(File(_dataSource.uri),
            viewType: _viewType);
    }
  }

  @override
  PlayerBackendKind get kind => PlayerBackendKind.videoPlayer;

  @override
  int? get textureId => null;

  @override
  NiumaPlayerValue get value => _value;

  @override
  Stream<NiumaPlayerValue> get valueStream => _valueController.stream;

  @override
  Stream<NiumaPlayerEvent> get eventStream => _eventController.stream;

  @override
  Future<void> initialize() async {
    _inner.addListener(_onInnerChanged);
    await _inner.initialize();
    _startPipEventListening();
  }

  void _startPipEventListening() {
    _pipEventSub = subscribePipEvents(_eventController.add);
  }

  /// 推导 [PlayerPhase]，优先级
  /// `error → opening → ended → playing → 无意图则 paused/ready →
  /// buffering → paused/ready`。
  ///
  /// playing 必须排在 buffering 前：video_player 的 Android 实现会在正常
  /// 播放中把 isBuffering 卡在 true，若 buffering 优先，phase 永远出不了
  /// buffering——皮肤 spinner 不灭、isPlaying 恒 false。
  ///
  /// [userWantsPlay] 是必需的：vp 的 `pause()` 只翻 isPlaying、不动
  /// isBuffering，而 ExoPlayer 暂停只改 playWhenReady、不改 playbackState，
  /// 收不到 bufferingEnd。因此在缓冲窗口内按暂停会永久卡在 buffering
  /// （按钮不翻转 + spinner 不灭）。语义对齐 1.x native 路径的
  /// `PlayerSession.userWantsPlay`：无播放意图时永不产出 buffering。
  @visibleForTesting
  static PlayerPhase derivePhaseFor(
    VideoPlayerValue v, {
    required bool userWantsPlay,
  }) {
    if (v.hasError) return PlayerPhase.error;
    if (!v.isInitialized) return PlayerPhase.opening;
    if (v.isCompleted) return PlayerPhase.ended;
    if (v.isPlaying) return PlayerPhase.playing;
    if (!userWantsPlay) {
      return v.position == Duration.zero
          ? PlayerPhase.ready
          : PlayerPhase.paused;
    }
    if (v.isBuffering) return PlayerPhase.buffering;
    if (v.position == Duration.zero) return PlayerPhase.ready;
    return PlayerPhase.paused;
  }

  void _onInnerChanged() {
    if (_disposed) return;
    final v = _inner.value;
    final buffered = v.buffered.isEmpty ? Duration.zero : v.buffered.last.end;
    final phase = derivePhaseFor(v, userWantsPlay: _userWantsPlay);
    // video_player 只有自由格式 errorDescription，包成 unknown 分类。
    final PlayerError? playerError = v.hasError
        ? PlayerError(
            category: PlayerErrorCategory.unknown,
            message: v.errorDescription ?? 'video_player error',
          )
        : null;
    final mapped = NiumaPlayerValue(
      phase: phase,
      position: v.position,
      duration: v.duration,
      size: v.size,
      bufferedPosition: buffered,
      playbackSpeed: v.playbackSpeed,
      error: playerError,
    );
    if (mapped != _value) {
      _value = mapped;
      if (!_valueController.isClosed) {
        _valueController.add(_value);
      }
    }
  }

  // mutate _inner 前先查 _disposed：dispose 期间 listener 可能同步调进来，
  // 撞 'VideoPlayerController used after disposed'。

  /// 最近一次的播放意图。底层拿不到（vp 不暴露 playWhenReady），必须自己
  /// 记——见 [derivePhaseFor] 的说明。任何会改变播放状态的路径都要维护它。
  bool _userWantsPlay = false;

  @override
  Future<void> play() async {
    if (_disposed) return;
    _userWantsPlay = true;
    return _inner.play();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    _userWantsPlay = false;
    return _inner.pause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (_disposed) return;
    return _inner.seekTo(position);
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (_disposed) return;
    return _inner.setPlaybackSpeed(speed);
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    return _inner.setVolume(volume);
  }

  @override
  Future<void> setLooping(bool looping) async {
    if (_disposed) return;
    return _inner.setLooping(looping);
  }

  /// 读当前窗口亮度（0..1）。失败返 0。
  @override
  Future<double> getBrightness() async {
    try {
      final r = await _systemChannel.invokeMethod<double>('getBrightness');
      return r ?? 0.0;
    } on PlatformException {
      return 0.0;
    }
  }

  /// 设置窗口亮度（0..1）。失败返 false。
  @override
  Future<bool> setBrightness(double value) async {
    try {
      final r = await _systemChannel.invokeMethod<bool>(
        'setBrightness',
        {'value': value.clamp(0.0, 1.0)},
      );
      return r ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 读系统媒体音量（0..1）。失败返 0。
  @override
  Future<double> getSystemVolume() async {
    try {
      final r = await _systemChannel.invokeMethod<double>('getSystemVolume');
      return r ?? 0.0;
    } on PlatformException {
      return 0.0;
    }
  }

  /// 设置系统媒体音量（0..1）。失败返 false。
  @override
  Future<bool> setSystemVolume(double value) async {
    try {
      final r = await _systemChannel.invokeMethod<bool>(
        'setSystemVolume',
        {'value': value.clamp(0.0, 1.0)},
      );
      return r ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 进入 PiP（iOS）。[aspectNum]/[aspectDen] 为首选宽高比；失败 /
  /// 不支持返 `false` 不抛。channel 键名保持 `textureId`（协议约定），
  /// 实际取 video_player 2.10+ 的 `playerId`。
  @override
  Future<bool> enterPictureInPicture({
    required int aspectNum,
    required int aspectDen,
    bool unsafeAutoBackground = false,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    final tid = _inner.playerId;
    // kUninitializedPlayerId == -1；未初始化时不能 PiP。
    if (tid < 0) return false;
    try {
      final result = await _pipChannel.invokeMethod<bool>(
        'enterPictureInPicture',
        <String, dynamic>{
          'textureId': tid,
          'aspectNum': aspectNum,
          'aspectDen': aspectDen,
          'unsafeAutoBackground': unsafeAutoBackground,
        },
      );
      return result ?? false;
    } on PlatformException catch (e, st) {
      // 不抛——失败默默返 false，让上层决定 UX。
      assert(() {
        // ignore: avoid_print
        print('[VideoPlayerBackend] enterPip failed: $e\n$st');
        return true;
      }());
      return false;
    }
  }

  /// 退出 PiP（iOS）。失败 / 不支持返 `false` 不抛。
  @override
  Future<bool> exitPictureInPicture() async {
    try {
      final result =
          await _pipChannel.invokeMethod<bool>('exitPictureInPicture');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 查询设备 + video_player 是否支持 PiP（iOS 15+）。失败返 `false` 不抛。
  @override
  Future<bool> queryPictureInPictureSupport() async {
    try {
      final result = await _pipChannel.invokeMethod<bool>(
        'queryPictureInPictureSupport',
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// iOS PiP 的 stock 控件由 AVKit 自动同步——已知不需要做事，显式 no-op。
  @override
  Future<void> updatePictureInPictureActions({
    required bool isPlaying,
  }) async {}

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _inner.removeListener(_onInnerChanged);
    // cancel 的是 bus 的 sub-listener，不触发 native EventChannel cancel。
    await _pipEventSub?.cancel();
    _pipEventSub = null;
    await _inner.dispose();
    await _valueController.close();
    await _eventController.close();
  }
}
