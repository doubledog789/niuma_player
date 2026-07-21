import 'dart:async';

import 'package:flutter/services.dart';

import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_backend.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/data/_pip_event_bus.dart';

/// 用于 texture 创建和设备指纹查询的全局 channel。
const MethodChannel _globalChannel = MethodChannel('cn.niuma/player');

/// 由 niuma_player 自家 Android 插件支撑的 [PlayerBackend]。
/// ExoPlayer 还是 IJK 由 native 侧按 `forceIjk` 决定，Dart 侧不做假设；
/// channel：`cn.niuma/player`（全局）+ `cn.niuma/player[/events]/<textureId>`（每实例）。
class NativeBackend extends PlayerBackend {
  NativeBackend(
    this._dataSource, {
    this.forceIjk = false,
    this.useAndroidPlatformView = false,
  });

  final NiumaDataSource _dataSource;

  /// 为 true 时 native 侧直接用 IJK，不再尝试 ExoPlayer（Exo 失败重试时传）。
  final bool forceIjk;

  /// 为 true 时走 PlatformView（`SurfaceView`）渲染路径，不分配
  /// SurfaceTexture。见 `NiumaPlayerOptions.useAndroidPlatformView`。
  final bool useAndroidPlatformView;

  int? _textureId;
  bool _isPlatformView = false;

  @override
  int? get androidPlatformViewId => _isPlatformView ? _textureId : null;
  String? _fingerprint;

  /// native 侧实际实例化的变体（`"exo"` / `"ijk"`），[initialize] 填充。
  String? _selectedVariant;
  String? get selectedVariant => _selectedVariant;


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

  /// [initialize] 期间由 native 侧返回的设备指纹。
  String? get fingerprint => _fingerprint;

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
        'forceIjk': forceIjk,
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
    _fingerprint = result['fingerprint'] as String?;
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
    // 共享 root listener，避开 EventChannel 单 listener cancel race
    //（见 _pip_event_bus.dart）。
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
        // 静默忽略——PiP 不可用时 EventChannel 也可能 error
      },
    );
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
    if (phase == PlayerPhase.error && !_eventController.isClosed) {
      _eventController.add(
        FallbackTriggered(
          FallbackReason.error,
          errorCode: errorCode == null ? null : '$errorCode@${positionMs}ms',
          errorCategory: playerError?.category,
        ),
      );
    }
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

  /// 供 [NiumaPlayerController] 在创建 texture 之前取设备指纹。
  static Future<String?> fetchDeviceFingerprint() async {
    final result = await _globalChannel.invokeMapMethod<String, dynamic>(
      'deviceFingerprint',
    );
    return result?['fingerprint'] as String?;
  }

  /// 查询 Android 进程堆上限（MB）；原生不可用返 null，调用方兜默认值。
  static Future<int?> fetchProcessHeapLimitMb() async {
    return _globalChannel.invokeMethod<int>('getProcessHeapLimitMb');
  }
}
