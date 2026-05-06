import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:niuma_player/src/domain/platform_bridge.dart';
import 'package:niuma_player/src/data/native_backend.dart';

/// 生产环境 [PlatformBridge]。
///
/// 在 iOS / Web 上从 SDK 侧合成 fingerprint，不走 Android 插件
/// （那些平台没有）。Android 上转发到
/// [NativeBackend.fetchDeviceFingerprint]。
class DefaultPlatformBridge implements PlatformBridge {
  const DefaultPlatformBridge();

  @override
  bool get isIOS {
    // Web 环境下 dart:io 的 Platform getter 会抛；先用 kIsWeb 拦掉。
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  @override
  bool get isWeb => kIsWeb;

  @override
  Future<String> deviceFingerprint() async {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) {
      return 'ios-${Platform.operatingSystemVersion}';
    }
    final fp = await NativeBackend.fetchDeviceFingerprint();
    return fp ?? 'unknown';
  }
}
