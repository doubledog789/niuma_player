/// 对 `dart:io` Platform / `kIsWeb` 与系统能力 channel 的薄间接层。
/// 存在的目的是让测试不引入 dart:io 也能注入 fake。
abstract class PlatformBridge {
  /// iOS 上为 true。驱动 "走 video_player → AVPlayer" 的路由。
  bool get isIOS;

  /// 在浏览器中运行时为 true。驱动 "走自家 WebVideoBackend（`<video>` +
  /// 按需 hls.js）" 的路由。
  bool get isWeb;

  /// 进程级堆上限（MB，非物理 RAM——Android 即 `memoryClass`）。
  /// [NiumaPlayerPool] 按它算容量才不会 OOM。iOS / Web 返默认值。
  Future<int> processHeapLimitMb();

  /// 保持 / 释放屏幕常亮（wakelock）。[NiumaPlayerController] 在 playing
  /// 边沿自动调用，多实例进程级计数归并，业务方一般无需手动调。
  Future<void> setKeepScreenOn(bool on);
}
