import 'dart:io' show Platform;

import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;

/// brightness / volume / wakelock 同款系统能力 channel。
const MethodChannel _systemChannel = MethodChannel('niuma_player/system');

/// 设备媒体能力探测（io 平台实现）。
class NiumaCapabilities {
  NiumaCapabilities._();

  static bool? _hevcCache;

  /// 本机是否能**硬解** H.265 / HEVC。
  ///
  /// 典型用途：源协商——业务据此决定向服务端请求 H.265 还是 H.264 源
  /// （具体协议字段由业务自定，SDK 不自动附加任何请求头）。
  ///
  /// - **iOS**：恒 `true`——iOS 11+ 系统级支持 HEVC 播放（A9+ 硬解、更老
  ///   设备系统软解），Flutter 可运行的 iOS 版本内无不可播场景。
  /// - **Android**：查 `MediaCodecList` 是否存在 `video/hevc` **硬件**解码器
  ///   （纯软解不算——低端机软解 1080p H.265 卡顿，给它下发 H.265 源反而劣化）。
  ///   进程内缓存，重复调用不再走 channel。
  ///
  /// 注意这是「有无硬解器」的声明性检测，个别设备解码器上了名单但实际解 10bit
  /// 花屏——服务端保留 H.264 线路配合多线路 failover 兜底。
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
}
