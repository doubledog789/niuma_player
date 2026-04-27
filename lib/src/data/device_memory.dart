import 'dart:async';

import 'package:flutter/services.dart';

/// Persistent "this device needs IJK" memory, keyed by device fingerprint.
///
/// Storage now lives on the native side (`DeviceMemoryStore` on Android,
/// SharedPreferences-backed) and is reached via the global `cn.niuma/player`
/// MethodChannel. The TTL/expiry comparison stays here in Dart so the
/// existing `DateTime Function() now` injection point — used by tests to
/// fast-forward the clock — keeps working without having to plumb a clock
/// through the channel.
///
/// Wire protocol (see `NiumaPlayerPlugin.kt`):
///   - `deviceMemory.get`   { fingerprint } → null | { expiresAt: int? }
///   - `deviceMemory.set`   { fingerprint, expiresAt: int? } → void
///   - `deviceMemory.unset` { fingerprint } → void
///   - `deviceMemory.clear` → void
///
/// `expiresAt: null` over the wire means "never expires"; absence of the
/// fingerprint key means "not marked".
class DeviceMemory {
  DeviceMemory({
    DateTime Function()? now,
    MethodChannel? channel,
  })  : _now = now ?? DateTime.now,
        _channel = channel ?? const MethodChannel('cn.niuma/player');

  final DateTime Function() _now;
  final MethodChannel _channel;

  /// Returns true if we previously recorded that [fingerprint] needs IJK and
  /// the record hasn't expired.
  Future<bool> shouldUseIjk(String fingerprint) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'deviceMemory.get',
      <String, dynamic>{'fingerprint': fingerprint},
    );
    if (result == null) return false;
    final expiresAt = (result['expiresAt'] as num?)?.toInt();
    if (expiresAt == null) return true;
    if (_now().millisecondsSinceEpoch >= expiresAt) {
      // Expired → eagerly clean up so we only pay the read cost once.
      try {
        await _channel.invokeMethod<void>(
          'deviceMemory.unset',
          <String, dynamic>{'fingerprint': fingerprint},
        );
      } catch (_) {
        // Best-effort: a failed unset just means we'll re-detect next time.
      }
      return false;
    }
    return true;
  }

  /// Records that [fingerprint] needs IJK. If [ttl] is null or zero, the
  /// record is permanent; otherwise it expires after [ttl] from now.
  Future<void> markIjkNeeded(
    String fingerprint, {
    Duration? ttl,
  }) async {
    final hasTtl = ttl != null && ttl > Duration.zero;
    final expiresAt = hasTtl
        ? _now().millisecondsSinceEpoch + ttl.inMilliseconds
        : null;
    await _channel.invokeMethod<void>(
      'deviceMemory.set',
      <String, dynamic>{
        'fingerprint': fingerprint,
        'expiresAt': expiresAt,
      },
    );
  }

  /// Clears every niuma_player memory entry (useful for debug UI).
  Future<void> clear() async {
    await _channel.invokeMethod<void>('deviceMemory.clear');
  }
}
