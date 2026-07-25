import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;

/// brightness / volume / wakelock 同款系统能力 channel。
const MethodChannel _systemChannel = MethodChannel('niuma_player/system');

/// 设备媒体能力探测（io 平台实现）。
class NiumaCapabilities {
  NiumaCapabilities._();

  static bool? _hevcCache;

  /// 本机是否能**硬解** H.265 / HEVC——iOS 恒 true（系统级支持）；
  /// Android 查 `MediaCodecList` 硬解器（纯软解不算，低端机会卡）。缓存。
  /// 声明性检测，个别设备仍可能花屏——保留 H.264 线路 failover 兜底。
  static Future<bool> supportsHevc() async {
    final cached = _hevcCache;
    if (cached != null) return cached;
    if (Platform.isIOS) return _hevcCache = true;
    try {
      final result =
          await _systemChannel.invokeMethod<bool>('supportsHevcDecoder');
      return _hevcCache = result ?? false;
    } on MissingPluginException {
      return _hevcCache = false;
    } on PlatformException {
      return _hevcCache = false;
    }
  }

  static int? _sdkIntCache;

  /// Android API level（`Build.VERSION.SDK_INT`）；非 Android / 查询失败返 0。
  /// 缓存。用于绕开个别版本的平台视图缺陷（见
  /// `NiumaPlayerController` 对 API 28 的降级）。
  static Future<int> androidSdkInt() async {
    final cached = _sdkIntCache;
    if (cached != null) return cached;
    if (Platform.isIOS) return _sdkIntCache = 0;
    try {
      final result =
          await _systemChannel.invokeMethod<int>('getAndroidSdkInt');
      return _sdkIntCache = result ?? 0;
    } on MissingPluginException {
      return _sdkIntCache = 0;
    } on PlatformException {
      return _sdkIntCache = 0;
    }
  }

  /// 仅测试用：清空进程内探测缓存。
  @visibleForTesting
  static void debugResetCaches() {
    _hevcCache = null;
    _sdkIntCache = null;
  }
}
