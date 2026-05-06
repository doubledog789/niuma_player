import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android multicast lock 控制器——SSDP 扫描期间申请，结束释放。
///
/// 非 Android 平台 no-op（iOS / Web 不需要 multicast lock）。
class MulticastLockController {
  MulticastLockController({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('niuma_player_dlna/multicast');

  final MethodChannel _channel;

  /// 申请 lock。Android 上调原生 WifiManager.MulticastLock；其他平台 no-op。
  Future<void> acquire() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('acquire');
    } catch (_) {
      // 忽略——失败 SSDP 仍可能扫到（视设备 / 路由器）
    }
  }

  /// 释放 lock。
  Future<void> release() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {
      // 忽略
    }
  }

  bool get _isAndroid =>
      defaultTargetPlatform == TargetPlatform.android && !kIsWeb;
}
