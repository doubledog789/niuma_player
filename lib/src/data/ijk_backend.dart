import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/data_source.dart';
import '../domain/player_backend.dart';
import '../domain/player_state.dart';

/// Global channel used for texture creation and device fingerprint lookup.
const MethodChannel _globalChannel = MethodChannel('cn.niuma/player');

/// [PlayerBackend] implementation backed by the Android-native IJK plugin.
///
/// Channel layout (see design doc §6.2):
///   - `cn.niuma/player`                       (global: create / fingerprint)
///   - `cn.niuma/player/<textureId>`           (per-instance: play/pause/...)
///   - `cn.niuma/player/events/<textureId>`    (per-instance events)
class IjkBackend implements PlayerBackend {
  IjkBackend(this._dataSource);

  final NiumaDataSource _dataSource;

  int? _textureId;
  String? _fingerprint;
  MethodChannel? _instanceChannel;
  EventChannel? _eventChannel;
  StreamSubscription<dynamic>? _eventSub;

  NiumaPlayerValue _value = NiumaPlayerValue.uninitialized();
  final StreamController<NiumaPlayerValue> _valueController =
      StreamController<NiumaPlayerValue>.broadcast();
  final StreamController<NiumaPlayerEvent> _eventController =
      StreamController<NiumaPlayerEvent>.broadcast();

  /// Resolves when the native `initialized` event arrives (IJK's onPrepared).
  /// Completed with an error if the first event we see is `error`. Ensures
  /// [initialize] has parity with video_player's "ready-to-play" semantics —
  /// play/seek commands fired right after initialize() succeed because the
  /// underlying IjkMediaPlayer is guaranteed prepared by then.
  final Completer<void> _preparedCompleter = Completer<void>();

  bool _disposed = false;

  /// Max time we wait for IJK's onPrepared before giving up. Network streams
  /// with huge manifests can take a while; 30s is generous.
  static const Duration _prepareTimeout = Duration(seconds: 30);

  @override
  PlayerBackendKind get kind => PlayerBackendKind.ijk;

  @override
  int? get textureId => _textureId;

  /// The device fingerprint returned by the native side during [initialize].
  /// Exposed so [NiumaPlayerController] can persist failure memory after a
  /// fallback has already happened (though in practice the controller fetches
  /// the fingerprint up front via [DeviceMemory]).
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
        if (_dataSource.headers != null) 'headers': _dataSource.headers,
      },
    );
    if (result == null) {
      throw PlatformException(
        code: 'ijk_create_failed',
        message: 'Native side returned null for create',
      );
    }
    final tid = result['textureId'];
    if (tid is! int) {
      throw PlatformException(
        code: 'ijk_create_bad_response',
        message: 'create did not return an int textureId: $result',
      );
    }
    _textureId = tid;
    _fingerprint = result['fingerprint'] as String?;

    _instanceChannel = MethodChannel('cn.niuma/player/$tid');
    _eventChannel = EventChannel('cn.niuma/player/events/$tid');
    _eventSub = _eventChannel!.receiveBroadcastStream().listen(
          _onEvent,
          onError: _onChannelError,
        );

    // Wait for the native `initialized` event (IJK's onPrepared). Without
    // this, callers that do `initialize(); play()` fire start() before the
    // player is ready, which IjkMediaPlayer silently drops.
    await _preparedCompleter.future.timeout(
      _prepareTimeout,
      onTimeout: () => throw PlatformException(
        code: 'ijk_prepare_timeout',
        message:
            'IJK prepareAsync did not finish within ${_prepareTimeout.inSeconds}s',
      ),
    );
  }

  void _onEvent(dynamic raw) {
    if (_disposed) return;
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    final event = map['event'] as String?;
    if (event == null) return;

    switch (event) {
      case 'initialized':
        final durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;
        final width = (map['width'] as num?)?.toDouble() ?? 0;
        final height = (map['height'] as num?)?.toDouble() ?? 0;
        _updateValue(_value.copyWith(
          initialized: true,
          duration: Duration(milliseconds: durationMs),
          size: Size(width, height),
        ));
        if (!_preparedCompleter.isCompleted) _preparedCompleter.complete();
        break;
      case 'bufferingStart':
        _updateValue(_value.copyWith(isBuffering: true));
        break;
      case 'bufferingEnd':
        _updateValue(_value.copyWith(isBuffering: false));
        break;
      case 'positionChanged':
        final pos = (map['positionMs'] as num?)?.toInt() ?? 0;
        _updateValue(_value.copyWith(
          position: Duration(milliseconds: pos),
        ));
        break;
      case 'completed':
        _updateValue(_value.copyWith(
          isPlaying: false,
          position: _value.duration,
        ));
        break;
      case 'videoSizeChanged':
        final width = (map['width'] as num?)?.toDouble() ?? 0;
        final height = (map['height'] as num?)?.toDouble() ?? 0;
        _updateValue(_value.copyWith(size: Size(width, height)));
        break;
      case 'playingChanged':
        final playing = map['isPlaying'] as bool? ?? false;
        _updateValue(_value.copyWith(isPlaying: playing));
        break;
      case 'error':
        final code = map['code']?.toString();
        final message = map['message']?.toString();
        _updateValue(_value.copyWith(errorMessage: message ?? code ?? 'error'));
        if (!_eventController.isClosed) {
          _eventController.add(
            FallbackTriggered(FallbackReason.error, errorCode: code),
          );
        }
        // If prepare never arrived, surface the error from initialize()
        // instead of leaving the caller hanging on the prepare completer.
        if (!_preparedCompleter.isCompleted) {
          _preparedCompleter.completeError(
            PlatformException(
              code: code ?? 'ijk_error',
              message: message ?? 'IjkMediaPlayer error',
            ),
          );
        }
        break;
    }
  }

  void _onChannelError(Object error, [StackTrace? stack]) {
    if (_disposed) return;
    _updateValue(_value.copyWith(errorMessage: error.toString()));
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
