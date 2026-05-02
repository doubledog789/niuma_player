import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/data_source.dart';
import '../domain/player_backend.dart';
import '../domain/player_state.dart';

/// 用于 texture 创建和设备指纹查询的全局 channel。
const MethodChannel _globalChannel = MethodChannel('cn.niuma/player');

/// 由 niuma_player 自家 Android 插件支撑的 [PlayerBackend]。
///
/// Dart 这一侧故意对底层具体跑哪个 native player 不做假设——这个选择
/// （硬解走 ExoPlayer，软解兜底走 IJK）由 `NiumaPlayerPlugin` 根据
/// `forceIjk` 标志和持久化的 `DeviceMemoryStore` 决定。
///
/// [initialize] 完成后，[selectedVariant] 报告实际选中的变体（"exo"
/// 或 "ijk"），[fromMemory] 报告本次选择是否由过去的失败记忆推动，
/// 而不是新一次的尝试。
///
/// 通讯协议：
///   - `cn.niuma/player`                       （全局：create / fingerprint）
///   - `cn.niuma/player/<textureId>`           （每个实例：play/pause/...）
///   - `cn.niuma/player/events/<textureId>`    （每个实例的状态流）
class NativeBackend implements PlayerBackend {
  NativeBackend(this._dataSource, {this.forceIjk = false});

  final NiumaDataSource _dataSource;

  /// 为 true 时，要求 native 侧直接用 IJK，不再尝试 ExoPlayer。
  /// Dart 侧 controller 在 Exo 失败后的重试中会传 true。
  final bool forceIjk;

  int? _textureId;
  String? _fingerprint;

  /// native 侧本次会话实际实例化的变体（`"exo"` 或 `"ijk"`）。
  /// 由 [initialize] 填充。
  String? _selectedVariant;
  String? get selectedVariant => _selectedVariant;

  /// 当 native 选 IJK 是因为 [DeviceMemoryStore] 说本设备过去需要它时，
  /// 此值为 true。由 [initialize] 填充。
  bool _fromMemory = false;
  bool get fromMemory => _fromMemory;

  MethodChannel? _instanceChannel;
  EventChannel? _eventChannel;
  StreamSubscription<dynamic>? _eventSub;

  NiumaPlayerValue _value = NiumaPlayerValue.uninitialized();
  final StreamController<NiumaPlayerValue> _valueController =
      StreamController<NiumaPlayerValue>.broadcast();
  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast();

  /// 当 native 离开 `phase=opening`（即进入 `ready` / `playing` 等，
  /// 或转到 `error`）时 resolve。
  final Completer<void> _preparedCompleter = Completer<void>();

  bool _disposed = false;

  /// 在没有任何 native 进度事件的情况下等待多久后判定 prepare 失败。
  /// 基于进度（而非绝对 wall-clock）：慢设备只要*在*进步就不会被误杀，
  /// 真正卡住的 native 侧仍能快速失败。
  static const Duration _prepareNoProgressTimeout = Duration(seconds: 20);

  Timer? _prepareWatchdog;

  /// 最近一次 native opening 阶段（`openInput`、`findStreamInfo` 等）。
  /// 用于在 timeout 错误信息里指明 prepare 卡在哪一步。
  String? _lastOpeningStage;

  /// 开始等待 prepare 的 wall-clock 时刻。仅用于装饰 timeout 错误信息。
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
    _fromMemory = result['fromMemory'] == true;

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
    _pipEventSub = _pipEventChannel.receiveBroadcastStream().listen(
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

  static const Map<String, PlayerPhase> _phaseFromString = <String, PlayerPhase>{
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

    // 把 terminal 错误冒泡出去，让 [NiumaPlayerController] 决定是否
    // 重试 / 回退。
    if (phase == PlayerPhase.error && !_eventController.isClosed) {
      _eventController.add(
        FallbackTriggered(
          FallbackReason.error,
          errorCode: errorCode == null
              ? null
              : '$errorCode@${positionMs}ms',
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

  static const MethodChannel _pipChannel = MethodChannel('niuma_player/pip');
  static const EventChannel _pipEventChannel =
      EventChannel('niuma_player/pip/events');

  StreamSubscription<dynamic>? _pipEventSub;

  /// 进入 PiP（Android）。
  ///
  /// 通过 'niuma_player/pip' channel 发到 NiumaPlayerPlugin（Android 原生）。
  /// 调用 Activity.enterPictureInPictureMode 不依赖 texture，故不传 textureId。
  /// 失败 / 不支持返 false 不抛。
  @override
  Future<bool> enterPictureInPicture({
    required int aspectNum,
    required int aspectDen,
  }) async {
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

  /// 退出 PiP（Android）。
  ///
  /// **注意：** Android 系统 PiP 没有"主动退出"API——用户拖回主 app 即退出。
  /// 本方法常返 false，仅保留接口对称性。
  @override
  Future<bool> exitPictureInPicture() async {
    try {
      final result = await _pipChannel.invokeMethod<bool>('exitPictureInPicture');
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
        // 尽力而为：吞掉 native dispose 错误，保证 Dart 资源始终被
        // 释放。
      }
    }
    await _valueController.close();
    await _eventController.close();
  }

  /// 便捷 helper，供 [NiumaPlayerController] 在创建任何 texture 之前
  /// 取设备指纹。
  static Future<String?> fetchDeviceFingerprint() async {
    final result = await _globalChannel.invokeMapMethod<String, dynamic>(
      'deviceFingerprint',
    );
    return result?['fingerprint'] as String?;
  }
}
