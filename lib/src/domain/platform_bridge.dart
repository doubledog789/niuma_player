/// 对 `dart:io` Platform / `kIsWeb` 和 native 设备指纹查询的薄间接层。
/// 存在的目的是让测试不引入 dart:io 也能注入 fake。
abstract class PlatformBridge {
  /// iOS 上为 true。驱动 "走 video_player → AVPlayer" 的路由。
  bool get isIOS;

  /// 在浏览器中运行时为 true。驱动 "走 video_player → <video>" 的路由
  /// （HLS 由 `video_player_web_hls` 注入 hls.js）。
  bool get isWeb;

  /// 当前设备的 SHA-1 指纹。硬件 / 软件形态完全一致的设备返回相同的
  /// 指纹，可作为 `DeviceMemoryStore` 的 key。
  Future<String> deviceFingerprint();
}
