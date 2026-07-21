import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel, PlatformException, MissingPluginException;

import 'package:niuma_player/src/domain/platform_bridge.dart';
import 'package:niuma_player/src/data/native_backend.dart';

/// brightness / volume / wakelock 共用的系统能力 channel（Android
/// `NiumaPlayerPlugin` / iOS `NiumaSystemPlugin` 两端注册同名）。
const MethodChannel _systemChannel = MethodChannel('niuma_player/system');

/// 生产环境 [PlatformBridge]：iOS / Web 侧合成 fingerprint，
/// Android 转发到 [NativeBackend.fetchDeviceFingerprint]。
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

  @override
  Future<int> processHeapLimitMb() async {
    // iOS / Web 无进程堆上限概念，返保守默认值落在中档容量。
    if (kIsWeb || Platform.isIOS) return 256;
    return await NativeBackend.fetchProcessHeapLimitMb() ?? 256;
  }

  @override
  Future<void> setKeepScreenOn(bool on) async {
    // web：浏览器播 <video> 有声时自身防熄屏，无需（也无统一 API）处理。
    if (kIsWeb) return;
    try {
      await _systemChannel.invokeMethod<void>(
        'setKeepScreenOn',
        {'on': on},
      );
    } on MissingPluginException {
      // 宿主没注册 system 插件（如纯 Dart 测试环境）：静默忽略。
    } on PlatformException {
      // Activity 已 detach 等：wakelock 失败不影响播放，静默忽略。
    }
  }
}
