import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/data_source.dart';
import '../domain/player_backend.dart';
import '../domain/player_state.dart';

/// Global channel used for texture creation and device fingerprint lookup.
const MethodChannel _globalChannel = MethodChannel('cn.niuma/player');

/// [PlayerBackend] backed by niuma_player's own Android plugin.
///
/// The Dart side is intentionally agnostic about which concrete native
/// player is running underneath — that choice (ExoPlayer for hardware
/// decode, IJK for software-decode rescue) is made by `NiumaPlayerPlugin`
/// based on the `forceIjk` flag and the persistent `DeviceMemoryStore`.
///
/// After [initialize] completes, [selectedVariant] reports which variant
/// was actually chosen ("exo" or "ijk"), and [fromMemory] reports whether
/// the choice was driven by past failure memory rather than a fresh try.
///
/// Wire protocol:
///   - `cn.niuma/player`                       (global: create / fingerprint)
///   - `cn.niuma/player/<textureId>`           (per-instance: play/pause/...)
///   - `cn.niuma/player/events/<textureId>`    (per-instance state stream)
class NativeBackend implements PlayerBackend {
  NativeBackend(this._dataSource, {this.forceIjk = false});

  final NiumaDataSource _dataSource;

  /// When true, the native side is asked to use IJK directly without
  /// trying ExoPlayer. The Dart-side controller passes this on its retry
  /// after an Exo failure.
  final bool forceIjk;

  int? _textureId;
  String? _fingerprint;

  /// Which variant the native side actually instantiated for this session
  /// (`"exo"` or `"ijk"`). Populated by [initialize].
  String? _selectedVariant;
  String? get selectedVariant => _selectedVariant;

  /// True when the native side picked IJK because [DeviceMemoryStore] said
  /// this device has previously needed it. Populated by [initialize].
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

  /// Resolves once the native side has left `phase=opening` (i.e. either
  /// reached `ready` / `playing` etc., or transitioned to `error`).
  final Completer<void> _preparedCompleter = Completer<void>();

  bool _disposed = false;

  /// How long we'll wait with zero native progress events before calling
  /// prepare a failure. Progress-based (not absolute wall-clock) so a slow
  /// device that *is* making progress isn't killed for taking a long total
  /// time, while a truly stuck native side still fails fast.
  static const Duration _prepareNoProgressTimeout = Duration(seconds: 20);

  Timer? _prepareWatchdog;

  /// Most recent native opening stage (`openInput`, `findStreamInfo`, …).
  /// Used in the timeout error message to pinpoint where prepare gave up.
  String? _lastOpeningStage;

  /// Wall-clock instant when we started waiting for prepare. Used only to
  /// decorate the timeout error message.
  DateTime? _prepareStartedAt;

  @override
  PlayerBackendKind get kind => PlayerBackendKind.native;

  @override
  int? get textureId => _textureId;

  /// The device fingerprint returned by the native side during [initialize].
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

    // Settle the prepare completer once native leaves the opening phase.
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

    // Surface terminal errors so [NiumaPlayerController] can decide whether
    // to retry / fall back.
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

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _prepareWatchdog?.cancel();
    _prepareWatchdog = null;
    await _eventSub?.cancel();
    final tid = _textureId;
    if (tid != null) {
      try {
        await _globalChannel.invokeMethod<void>(
          'dispose',
          <String, dynamic>{'textureId': tid},
        );
      } catch (_) {
        // Best-effort: swallow native dispose errors so we always free Dart
        // resources.
      }
    }
    await _valueController.close();
    await _eventController.close();
  }

  /// Convenience helper used by [NiumaPlayerController] to fetch the device
  /// fingerprint before any texture has been created.
  static Future<String?> fetchDeviceFingerprint() async {
    final result = await _globalChannel.invokeMapMethod<String, dynamic>(
      'deviceFingerprint',
    );
    return result?['fingerprint'] as String?;
  }
}
