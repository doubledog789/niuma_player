import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../domain/data_source.dart';
import '../domain/player_backend.dart';
import '../domain/player_state.dart';

/// 包装 `package:video_player` 的 [PlayerBackend] 实现。
class VideoPlayerBackend implements PlayerBackend {
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
  }

  /// 从 [VideoPlayerValue] 推导 [PlayerPhase]。
  ///
  /// 优先级：`error → opening → ended → buffering → playing → paused/ready`。
  /// video_player 仅在 looping 为 OFF 时才会触发 `isCompleted`，所以这里
  /// 可以把它当作权威的 end-of-media 信号来用。
  PlayerPhase _derivePhase(VideoPlayerValue v) {
    if (v.hasError) return PlayerPhase.error;
    if (!v.isInitialized) return PlayerPhase.opening;
    if (v.isCompleted) return PlayerPhase.ended;
    if (v.isBuffering) return PlayerPhase.buffering;
    if (v.isPlaying) return PlayerPhase.playing;
    // 已初始化、未播放、未 buffering、未结束：
    //   - position == 0  → ready（刚打开，从未播过）
    //   - position > 0   → paused（之前播过）
    if (v.position == Duration.zero) return PlayerPhase.ready;
    return PlayerPhase.paused;
  }

  void _onInnerChanged() {
    if (_disposed) return;
    final v = _inner.value;
    // video_player 把已缓冲段以 DurationRange 列表形式上报；UI 关心的是
    // "已预加载到哪儿"，也就是最后一段的尾端。空列表 → 还没有 buffer
    // 信息。
    final buffered =
        v.buffered.isEmpty ? Duration.zero : v.buffered.last.end;
    final phase = _derivePhase(v);
    // video_player 只给出自由格式的 `errorDescription`——没有错误码，
    // 没有分类。包成 `unknown` 让消费方仍能拿到结构化的 [PlayerError]
    // 对象；切到 IJK 是唯一真正的恢复路径，因此除了"是的，出错了"
    // 之外的细节在这里也没什么价值。
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
      // video_player 通过 `value.errorDescription` 暴露错误；我们重新
      // 以 `FallbackTriggered` 发出，让 controller 可以响应。
      _eventController.add(
        FallbackTriggered(
          FallbackReason.error,
          errorCode: v.errorDescription,
          errorCategory: PlayerErrorCategory.unknown,
        ),
      );
    }
  }

  @override
  Future<void> play() => _inner.play();

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> seekTo(Duration position) => _inner.seekTo(position);

  @override
  Future<void> setSpeed(double speed) => _inner.setPlaybackSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _inner.setVolume(volume);

  @override
  Future<void> setLooping(bool looping) => _inner.setLooping(looping);

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

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _inner.removeListener(_onInnerChanged);
    await _inner.dispose();
    await _valueController.close();
    await _eventController.close();
  }
}
