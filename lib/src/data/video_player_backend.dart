import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_backend.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/data/_pip_event_bus.dart';

/// 包装 `package:video_player` 的 [PlayerBackend] 实现。
class VideoPlayerBackend extends PlayerBackend {
  VideoPlayerBackend(this._dataSource);

  final NiumaDataSource _dataSource;

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

  VideoPlayerController _buildController() {
    final headers = _dataSource.headers ?? const <String, String>{};
    switch (_dataSource.type) {
      case NiumaSourceType.network:
        return VideoPlayerController.networkUrl(
          Uri.parse(_dataSource.uri),
          httpHeaders: headers,
        );
      case NiumaSourceType.asset:
        return VideoPlayerController.asset(_dataSource.uri);
      case NiumaSourceType.file:
        return VideoPlayerController.file(File(_dataSource.uri));
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
    // 共享 [pipEventBus] root listener，避开 EventChannel 单 listener
    // cancel race（见 _pip_event_bus.dart）。
    _pipEventSub = pipEventBus().listen(
      (dynamic data) {
        if (data is! Map) return;
        final event = data['event'];
        if (event is! String) return;
        switch (event) {
          case 'pipStarted':
            _eventController.add(const PipModeChanged(isInPip: true));
          case 'pipStopped':
            _eventController.add(const PipModeChanged(isInPip: false));
          case 'playPauseToggle':
            _eventController
                .add(const PipRemoteAction(action: 'playPauseToggle'));
        }
      },
      onError: (Object error) {
        // 静默忽略——PiP 不可用时 root bus 也可能 error。
      },
    );
  }

  /// 推导 [PlayerPhase]，优先级
  /// `error → opening → ended → buffering → playing → paused/ready`。
  PlayerPhase _derivePhase(VideoPlayerValue v) {
    if (v.hasError) return PlayerPhase.error;
    if (!v.isInitialized) return PlayerPhase.opening;
    if (v.isCompleted) return PlayerPhase.ended;
    if (v.isBuffering) return PlayerPhase.buffering;
    if (v.isPlaying) return PlayerPhase.playing;
    if (v.position == Duration.zero) return PlayerPhase.ready;
    return PlayerPhase.paused;
  }

  void _onInnerChanged() {
    if (_disposed) return;
    final v = _inner.value;
    final buffered = v.buffered.isEmpty ? Duration.zero : v.buffered.last.end;
    final phase = _derivePhase(v);
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
      error: playerError,
    );
    if (mapped != _value) {
      _value = mapped;
      if (!_valueController.isClosed) {
        _valueController.add(_value);
      }
    }
    if (v.hasError && !_eventController.isClosed) {
      _eventController.add(
        FallbackTriggered(
          FallbackReason.error,
          errorCode: v.errorDescription,
          errorCategory: PlayerErrorCategory.unknown,
        ),
      );
    }
  }

  // mutate _inner 前先查 _disposed：dispose 期间 listener 可能同步调进来，
  // 撞 'VideoPlayerController used after disposed'。

  @override
  Future<void> play() async {
    if (_disposed) return;
    return _inner.play();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
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
