import 'dart:async';

import 'package:flutter/services.dart';

/// "本设备需要 IJK" 的持久化记忆，按设备指纹索引。
///
/// 存储现在落在 native 侧（Android 的 `DeviceMemoryStore`，由
/// SharedPreferences 支撑），通过全局 `cn.niuma/player` MethodChannel
/// 访问。TTL / 过期比较仍留在 Dart 这边，让原有的
/// `DateTime Function() now` 注入点（测试用来快进时钟）继续可用，
/// 而不必把 clock 透过 channel 传过去。
///
/// 通讯协议（见 `NiumaPlayerPlugin.kt`）：
///   - `deviceMemory.get`   { fingerprint } → null | { expiresAt: int? }
///   - `deviceMemory.set`   { fingerprint, expiresAt: int? } → void
///   - `deviceMemory.unset` { fingerprint } → void
///   - `deviceMemory.clear` → void
///
/// 通讯中 `expiresAt: null` 表示"永不过期"；fingerprint key 不存在
/// 表示"未标记"。
class DeviceMemory {
  DeviceMemory({
    DateTime Function()? now,
    MethodChannel? channel,
  })  : _now = now ?? DateTime.now,
        _channel = channel ?? const MethodChannel('cn.niuma/player');

  final DateTime Function() _now;
  final MethodChannel _channel;

  /// 若之前记录过 [fingerprint] 需要 IJK 且尚未过期，返回 true。
  Future<bool> shouldUseIjk(String fingerprint) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'deviceMemory.get',
      <String, dynamic>{'fingerprint': fingerprint},
    );
    if (result == null) return false;
    final expiresAt = (result['expiresAt'] as num?)?.toInt();
    if (expiresAt == null) return true;
    if (_now().millisecondsSinceEpoch >= expiresAt) {
      // 已过期 → 主动清理，只承担一次读取成本。
      try {
        await _channel.invokeMethod<void>(
          'deviceMemory.unset',
          <String, dynamic>{'fingerprint': fingerprint},
        );
      } catch (_) {
        // 尽力而为：unset 失败只会让下次再做一遍探测。
      }
      return false;
    }
    return true;
  }

  /// 记录 [fingerprint] 需要 IJK。[ttl] 为 null 或 0 时为永久记录；
  /// 否则在距 now 之后 [ttl] 过期。
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

  /// 清空所有 niuma_player 记忆条目（用于 debug UI）。
  Future<void> clear() async {
    await _channel.invokeMethod<void>('deviceMemory.clear');
  }
}
