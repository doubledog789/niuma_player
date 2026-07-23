import 'package:flutter/foundation.dart' show immutable;
import 'package:meta/meta.dart' show experimental;

/// 调整 [NiumaPlayerController] 行为的选项。所有字段都有合理默认值。
@immutable
class NiumaPlayerOptions {
  const NiumaPlayerOptions({
    this.initTimeout = const Duration(seconds: 30),
    this.forceIjkOnAndroid = false,
    this.unsafePipAutoBackgroundOnEnter = false,
    this.rollbackOnSwitchFailure = true,
    this.autoFailoverOnInitialError = true,
    this.useAndroidPlatformView = false,
    this.manageScreenWakelock = true,
  });

  /// backend 初始化的 wall-clock 上限；超时视作失败（Android 上以 IJK 重试）。
  /// vp 主路径只靠本超时兜底；IJK 路径另有 backend 内 20s 无进度 watchdog
  /// 与 FFmpeg 层 15s 网络超时。
  final Duration initTimeout;

  /// Android 上绕过 video_player 主路径直接走 IJK 软解（紧急覆盖 / A/B 用）。
  /// iOS 和 Web 忽略本标志。
  final bool forceIjkOnAndroid;

  /// Android 上把视频渲染从 Flutter Texture 切到 PlatformView（SurfaceView
  /// 原生缩放），画质上限更高。默认 false（opt-in）；iOS / Web 忽略。
  /// 主路径映射为 video_player 的 `VideoViewType.platformView`，IJK 兜底
  /// 路径走自家 Hybrid Composition——两条路径均可根治部分 ROM 的有声黑屏。
  /// 注意：首帧略晚（等 surfaceCreated），个别 ROM 叠层需真机回归。
  final bool useAndroidPlatformView;

  /// 播放中自动保持屏幕常亮，暂停 / 结束 / dispose 时释放；多 controller
  /// 以进程级计数归并。默认 `true`，业务自管亮屏策略时置 `false`。
  final bool manageScreenWakelock;

  /// **⚠️ App Store 不兼容**——启用后 iOS 端进 PiP 时调私有 API `suspend`
  /// 模拟 home 键让小窗立刻飘出，host app 必被拒审，仅限内部分发。
  /// Android / Web 忽略。默认 `false`（合规）。
  @experimental
  final bool unsafePipAutoBackgroundOnEnter;

  /// 用户主动 switchLine 失败时是否自动回滚到原线路（保留 position /
  /// wasPlaying）。默认 `true`。切换失败无论回滚成败都 emit
  /// [LineSwitchFailed]（供上报）；回滚成功不 rethrow，回滚也失败才 rethrow。
  /// 与 [autoFailoverOnInitialError] 独立。
  final bool rollbackOnSwitchFailure;

  /// 多线路时首次 initialize 是否把**全部线路**按 priority 升序遍历（含默认
  /// 线路——defaultLine 指向非最低 priority 线路时它不保证先试），全失败才
  /// 抛最后一条错误 → `PlayerPhase.error`。默认 `true`；单线路本 flag 无效。
  final bool autoFailoverOnInitialError;
}
