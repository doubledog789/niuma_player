/// 对 `dart:io` Platform / `kIsWeb` 和 native 设备指纹查询的薄间接层。
/// 存在的目的是让测试不引入 dart:io 也能注入 fake。
abstract class PlatformBridge {
  /// iOS 上为 true。驱动 "走 video_player → AVPlayer" 的路由。
  bool get isIOS;

  /// 在浏览器中运行时为 true。驱动 "走 video_player → <video>" 的路由
  /// （HLS 由 `video_player_web_hls` 注入 hls.js）。
  bool get isWeb;

  /// 当前设备的稳定指纹（同形态设备相同），供诊断 / 统计。
  Future<String> deviceFingerprint();

  /// 进程级堆上限（MB，非物理 RAM——Android 即 `memoryClass`）。
  /// [NiumaPlayerPool] 按它算容量才不会 OOM。iOS / Web 返默认值。
  Future<int> processHeapLimitMb();

  /// 保持 / 释放屏幕常亮（wakelock）。[NiumaPlayerController] 在 playing
  /// 边沿自动调用，多实例进程级计数归并，业务方一般无需手动调。
  Future<void> setKeepScreenOn(bool on);
}
