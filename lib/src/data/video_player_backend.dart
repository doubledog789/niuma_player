import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../domain/data_source.dart';
import '../domain/player_backend.dart';
import '../domain/player_state.dart';
import '_pip_event_bus.dart';

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
    // 监听的是 [pipEventBus]——SDK 进程级 lazy singleton broadcast，跟
    // NativeBackend 共用同一 root listener。backend dispose 时 cancel
    // 的是这个 Dart-side sub，不会向 native 端发 cancel 消息，避开
    // Flutter engine EventChannel 单 listener 模型在 controller 复用时
    // 的 cancel race。详见 _pip_event_bus.dart 头注释。
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
        // 静默忽略——PiP 不可用时 root bus 也可能 error
      },
    );
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

  // 所有 mutate _inner 的入口都先查 _disposed：dispose 期间 ChangeNotifier
  // 还可能 flush 最后一次 notify，listener 同步调进来时 _inner 可能正在
  // dispose。撞 'VideoPlayerController used after disposed' 的根因就在这。
  // 已 disposed 直接 no-op——SDK 不该让调用方关心 race timing。

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

  /// 进入 PiP（iOS）。
  ///
  /// 通过 `niuma_player/pip` channel 发到 NiumaPipPlugin（iOS 原生）。
  ///
  /// [aspectNum] / [aspectDen] 为视频宽高比的整数分子/分母，传给原生侧
  /// `AVPictureInPictureController` 设置首选比例。
  ///
  /// 实现细节：video_player 2.10+ 将内部播放器 ID 从 `textureId` 改名为
  /// `playerId`（`@visibleForTesting`）。iOS 原生 NiumaPipPlugin（Task 10）
  /// 通过该 ID 在 `playersByIdentifier` 字典里查找对应的 `FVPVideoPlayer`
  /// 进而拿到 `AVPlayer`。channel 参数键名保持 `textureId` 以与协议约定
  /// 保持一致（Task 10 按同名解析）。
  ///
  /// 失败 / 不支持返 `false` 不抛。
  @override
  Future<bool> enterPictureInPicture({
    required int aspectNum,
    required int aspectDen,
    bool unsafeAutoBackground = false,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    final tid = _inner.playerId;
    // kUninitializedPlayerId == -1；未初始化时不能 PiP
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
      // 不抛——失败默默返 false，让上层决定 UX
      assert(() {
        // ignore: avoid_print
        print('[VideoPlayerBackend] enterPip failed: $e\n$st');
        return true;
      }());
      return false;
    }
  }

  /// 退出 PiP（iOS）。
  ///
  /// 通过 `niuma_player/pip` channel 通知 NiumaPipPlugin 退出画中画。
  /// 失败 / 不支持返 `false` 不抛。
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

  /// 查询设备 + video_player 是否支持 PiP（iOS 15+）。
  ///
  /// 通过 `niuma_player/pip` channel 查询 NiumaPipPlugin。
  /// 不支持 / 查询失败返 `false` 不抛。
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

  /// iOS 系统 PiP 用 AVPictureInPictureController + AVPlayer，stock
  /// play/pause 控件由 AVKit 自动同步——这里 no-op，跟 PlayerBackend
  /// 默认行为一致，只是显式标记表明"已知不需要做事"。
  @override
  Future<void> updatePictureInPictureActions({
    required bool isPlaying,
  }) async {}

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _inner.removeListener(_onInnerChanged);
    // _pipEventSub 是 [_pipEventBus] 的 sub-listener，cancel 它不触发
    // native 端 EventChannel cancel——所以这里不会再撞 "No active stream
    // to cancel"。root sub 持续 hold 整个进程，由 OS 在进程退出时清理。
    await _pipEventSub?.cancel();
    _pipEventSub = null;
    await _inner.dispose();
    await _valueController.close();
    await _eventController.close();
  }
}
