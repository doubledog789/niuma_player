import 'dart:async';

import 'package:flutter/services.dart';

import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_backend.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/data/_pip_event_bus.dart';

/// 用于 texture 创建 / 释放的全局 channel。
const MethodChannel _globalChannel = MethodChannel('cn.niuma/player');

/// 由 niuma_player 自家 Android 插件支撑的 [PlayerBackend]。
/// 2.0 起 native 侧只承载 IJK 软解兜底（Android 主路径走官方 video_player）；
/// channel：`cn.niuma/player`（全局）+ `cn.niuma/player[/events]/<textureId>`（每实例）。
class NativeBackend extends PlayerBackend {
  NativeBackend(
    this._dataSource, {
    this.useAndroidPlatformView = false,
  });

  final NiumaDataSource _dataSource;

  /// 为 true 时走 PlatformView（`SurfaceView`）渲染路径，不分配
  /// SurfaceTexture。见 `NiumaPlayerOptions.useAndroidPlatformView`。
  final bool useAndroidPlatformView;

  int? _textureId;
  bool _isPlatformView = false;

  @override
  int? get androidPlatformViewId => _isPlatformView ? _textureId : null;

  /// native 侧实例化的变体。2.0 起恒 `"ijk"`，仅用于超时错误信息。
  String? _selectedVariant;


  static const MethodChannel _systemChannel =
      MethodChannel('niuma_player/system');

  MethodChannel? _instanceChannel;
  EventChannel? _eventChannel;
  StreamSubscription<dynamic>? _eventSub;

  NiumaPlayerValue _value = NiumaPlayerValue.uninitialized();
  final StreamController<NiumaPlayerValue> _valueController =
      StreamController<NiumaPlayerValue>.broadcast();
  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast();

  /// native 离开 `phase=opening`（进 ready/playing 或 error）时 resolve。
  final Completer<void> _preparedCompleter = Completer<void>();

  bool _disposed = false;

  /// 无进度事件多久判定 prepare 失败——按进度而非 wall-clock，慢设备不误杀。
  static const Duration _prepareNoProgressTimeout = Duration(seconds: 20);

  Timer? _prepareWatchdog;

  /// 最近一次 native opening 阶段，用于 timeout 错误信息定位卡点。
  String? _lastOpeningStage;

  /// 开始等待 prepare 的时刻，仅用于装饰 timeout 错误信息。
  DateTime? _prepareStartedAt;

  @override
  PlayerBackendKind get kind => PlayerBackendKind.native;

  @override
  int? get textureId => _textureId;

  @override
  NiumaPlayerValue get value => _value;

  @override
  Stream<NiumaPlayerValue> get valueStream => _valueController.stream;

  @override
  Stream<NiumaPlayerEvent> get eventStream => _eventController.stream;

  @override
  Future<void> initialize() async {
    final result = await _globalChannel.invokeMapMethod<String, dynamic>(
      'create',
      <String, dynamic>{
        'uri': _dataSource.uri,
        'type': _dataSource.type.name,
        'useAndroidPlatformView': useAndroidPlatformView,
        if (_dataSource.headers != null) 'headers': _dataSource.headers,
      },
    );
    if (result == null) {
      throw PlatformException(
        code: 'native_create_failed',
        message: 'Native side returned null for create',
      );
    }
    final tid = result['textureId'];
    if (tid is! int) {
      throw PlatformException(
        code: 'native_create_bad_response',
        message: 'create did not return an int textureId: $result',
      );
    }
    _textureId = tid;
    _selectedVariant = result['selectedVariant'] as String?;
    _isPlatformView = result['isPlatformView'] == true;

    _instanceChannel = MethodChannel('cn.niuma/player/$tid');
    _eventChannel = EventChannel('cn.niuma/player/events/$tid');
    _eventSub = _eventChannel!.receiveBroadcastStream().listen(
          _onEvent,
          onError: _onChannelError,
        );

    _prepareStartedAt = DateTime.now();
    _bumpPrepareWatchdog();
    try {
      await _preparedCompleter.future;
    } finally {
      _prepareWatchdog?.cancel();
      _prepareWatchdog = null;
    }
    _startPipEventListening();
  }

  void _startPipEventListening() {
    _pipEventSub = subscribePipEvents(_eventController.add);
  }

  void _bumpPrepareWatchdog() {
    if (_preparedCompleter.isCompleted || _disposed) return;
    _prepareWatchdog?.cancel();
    _prepareWatchdog = Timer(_prepareNoProgressTimeout, () {
      if (_preparedCompleter.isCompleted || _disposed) return;
      final elapsed = _prepareStartedAt == null
          ? Duration.zero
          : DateTime.now().difference(_prepareStartedAt!);
      _preparedCompleter.completeError(
        PlatformException(
          code: 'native_prepare_timeout',
          message:
              'Native prepare stalled for ${_prepareNoProgressTimeout.inSeconds}s '
              '(total elapsed ${elapsed.inSeconds}s, '
              'last stage=${_lastOpeningStage ?? "<none>"}, '
              'variant=${_selectedVariant ?? "<unknown>"})',
        ),
      );
    });
  }

  static const Map<String, PlayerPhase> _phaseFromString =
      <String, PlayerPhase>{
    'idle': PlayerPhase.idle,
    'opening': PlayerPhase.opening,
    'ready': PlayerPhase.ready,
    'playing': PlayerPhase.playing,
    'paused': PlayerPhase.paused,
    'buffering': PlayerPhase.buffering,
    'ended': PlayerPhase.ended,
    'error': PlayerPhase.error,
  };

  static const Map<String, PlayerErrorCategory> _categoryFromString =
      <String, PlayerErrorCategory>{
    'transient': PlayerErrorCategory.transient,
    'codecUnsupported': PlayerErrorCategory.codecUnsupported,
    'network': PlayerErrorCategory.network,
    'terminal': PlayerErrorCategory.terminal,
    'unknown': PlayerErrorCategory.unknown,
  };

  void _onEvent(dynamic raw) {
    if (_disposed) return;
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);

    final phaseStr = map['phase'] as String?;
    if (phaseStr == null) return;
    final phase = _phaseFromString[phaseStr] ?? PlayerPhase.idle;

    final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;
    final durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;
    final bufferedMs = (map['bufferedMs'] as num?)?.toInt() ?? 0;
    final width = (map['width'] as num?)?.toDouble() ?? 0;
    final height = (map['height'] as num?)?.toDouble() ?? 0;
    final openingStage = map['openingStage'] as String?;
    final errorCode = map['errorCode']?.toString();
    final errorMessage = map['errorMessage'] as String?;
    final errorCategoryStr = map['errorCategory'] as String?;

    if (openingStage != null) {
      _lastOpeningStage = openingStage;
    }

    if (!_preparedCompleter.isCompleted) {
      _bumpPrepareWatchdog();
    }

    final PlayerError? playerError;
    if (phase == PlayerPhase.error) {
      playerError = PlayerError(
        category: _categoryFromString[errorCategoryStr] ??
            PlayerErrorCategory.unknown,
        message: errorMessage ?? 'native player error',
        code: errorCode,
      );
    } else {
      playerError = null;
    }

    final next = NiumaPlayerValue(
      phase: phase,
      position: Duration(milliseconds: positionMs),
      duration: Duration(milliseconds: durationMs),
      size: Size(width, height),
      bufferedPosition: Duration(milliseconds: bufferedMs),
      openingStage: openingStage,
      // native 事件不上报速度，携带前值，防 setSpeed 后被打回 1.0。
      playbackSpeed: _value.playbackSpeed,
      error: playerError,
    );
    _updateValue(next);

    // 一旦 native 离开 opening 阶段就 settle prepare completer。
    if (!_preparedCompleter.isCompleted) {
      if (phase == PlayerPhase.error) {
        _preparedCompleter.completeError(
          PlatformException(
            code: errorCode ?? 'native_error',
            message: errorMessage ?? 'native error before first frame',
          ),
        );
      } else if (phase != PlayerPhase.idle && phase != PlayerPhase.opening) {
        _preparedCompleter.complete();
      }
    }

    // 错误冒泡给 [NiumaPlayerController] 决定是否重试 / 回退。
  }

  void _onChannelError(Object error, [StackTrace? stack]) {
    if (_disposed) return;
    _updateValue(_value.copyWith(
      phase: PlayerPhase.error,
      error: PlayerError(
        category: PlayerErrorCategory.unknown,
        message: error.toString(),
      ),
    ));
  }

  void _updateValue(NiumaPlayerValue next) {
    if (_disposed) return;
    if (next == _value) return;
    _value = next;
    if (!_valueController.isClosed) {
      _valueController.add(next);
    }
  }

  Map<String, dynamic> _argsWithId([Map<String, dynamic>? extra]) {
    return <String, dynamic>{
      'textureId': _textureId,
      if (extra != null) ...extra,
    };
  }

  @override
  Future<void> play() async {
    await _instanceChannel?.invokeMethod<void>('play', _argsWithId());
  }

  @override
  Future<void> pause() async {
    await _instanceChannel?.invokeMethod<void>('pause', _argsWithId());
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _instanceChannel?.invokeMethod<void>(
      'seekTo',
      _argsWithId(<String, dynamic>{'positionMs': position.inMilliseconds}),
    );
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _instanceChannel?.invokeMethod<void>(
      'setSpeed',
      _argsWithId(<String, dynamic>{'speed': speed}),
    );
    _updateValue(_value.copyWith(playbackSpeed: speed));
  }

  @override
  Future<void> setVolume(double volume) async {
    await _instanceChannel?.invokeMethod<void>(
      'setVolume',
      _argsWithId(<String, dynamic>{'volume': volume}),
    );
  }

  @override
  Future<void> setLooping(bool looping) async {
    await _instanceChannel?.invokeMethod<void>(
      'setLooping',
      _argsWithId(<String, dynamic>{'looping': looping}),
    );
  }

  /// 读当前窗口亮度（0..1）。
  @override
  Future<double> getBrightness() async {
    try {
      final r = await _systemChannel.invokeMethod<double>('getBrightness');
      return r ?? 0.0;
    } on PlatformException {
      return 0.0;
    }
  }

  /// 设置窗口亮度（0..1）。
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

  /// 读系统媒体音量（0..1）。
  @override
  Future<double> getSystemVolume() async {
    try {
      final r = await _systemChannel.invokeMethod<double>('getSystemVolume');
      return r ?? 0.0;
    } on PlatformException {
      return 0.0;
    }
  }

  /// 设置系统媒体音量（0..1）。
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

  static const MethodChannel _pipChannel = MethodChannel('niuma_player/pip');

  /// 监听共享 [pipEventBus]——避开 EventChannel 单 listener race。
  StreamSubscription<dynamic>? _pipEventSub;

  /// 进入 PiP（Android）。失败 / 不支持返 false 不抛。
  @override
  Future<bool> enterPictureInPicture({
    required int aspectNum,
    required int aspectDen,
    bool unsafeAutoBackground = false,
  }) async {
    // unsafeAutoBackground 是 iOS-only hack，Android 原生 PiP 立即生效，忽略。
    try {
      final result = await _pipChannel.invokeMethod<bool>(
        'enterPictureInPicture',
        <String, dynamic>{
          'aspectNum': aspectNum,
          'aspectDen': aspectDen,
        },
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 退出 PiP（Android）。系统无"主动退出"API，常返 false，仅保留接口对称。
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

  /// 查询设备 + Activity 是否支持 PiP（Android 8.0+ + manifest 声明）。
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

  /// 更新 PiP 窗 RemoteAction 图标（播 → pause icon，停 → play icon）。
  /// 失败静默忽略，不影响播放。
  @override
  Future<void> updatePictureInPictureActions({required bool isPlaying}) async {
    try {
      await _pipChannel.invokeMethod<void>(
        'updatePictureInPictureActions',
        <String, dynamic>{'isPlaying': isPlaying},
      );
    } on PlatformException {
      // 设备不支持 / Activity 已 detach 等：忽略。
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // 仍在 await initialize() 的调用方立刻失败，别等 initTimeout 兜底
    //（更别让重试链在已 dispose 的实例上继续拉起僵尸播放器）。
    if (!_preparedCompleter.isCompleted) {
      _preparedCompleter.completeError(
        StateError('NativeBackend disposed before prepared'),
      );
      _preparedCompleter.future.ignore();
    }
    _prepareWatchdog?.cancel();
    _prepareWatchdog = null;
    await _eventSub?.cancel();
    await _pipEventSub?.cancel();
    _pipEventSub = null;
    final tid = _textureId;
    if (tid != null) {
      try {
        await _globalChannel.invokeMethod<void>(
          'dispose',
          <String, dynamic>{'textureId': tid},
        );
      } catch (_) {
        // 吞掉 native dispose 错误，保证 Dart 资源始终被释放。
      }
    }
    await _valueController.close();
    await _eventController.close();
  }

  /// 查询 Android 进程堆上限（MB）；原生不可用返 null，调用方兜默认值。
  static Future<int?> fetchProcessHeapLimitMb() async {
    return _globalChannel.invokeMethod<int>('getProcessHeapLimitMb');
  }
}
