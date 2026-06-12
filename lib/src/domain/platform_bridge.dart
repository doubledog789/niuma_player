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

  /// 当前**进程级**堆上限，单位 MB（不是设备物理 RAM）。
  ///
  /// 即使在 12GB RAM 的设备上，单个 app 进程仍被系统 cap 在一个远小于
  /// 物理内存的堆上限（Android 上即 `ActivityManager.memoryClass`，常见
  /// 128 / 192 / 256 / 512MB）。同时存活的播放器 / 解码 buffer 都吃这块
  /// 堆——所以 [NiumaPlayerPool] 按这个值（而非 RAM）算容量才不会 OOM。
  ///
  /// iOS / Web 没有等价概念，返回合理默认值。
  Future<int> processHeapLimitMb();

  /// 保持 / 释放「屏幕常亮」（wakelock），防播放中自动熄屏。
  ///
  /// Android 走 Activity window 的 `FLAG_KEEP_SCREEN_ON`，iOS 走
  /// `UIApplication.isIdleTimerDisabled`，web no-op（浏览器播 `<video>`
  /// 有声时自身防熄屏）。[NiumaPlayerController] 在 playing 边沿自动调用
  /// （见 `NiumaPlayerOptions.manageScreenWakelock`），多实例以进程级计数
  /// 归并——业务方一般无需手动调用。
  Future<void> setKeepScreenOn(bool on);
}
