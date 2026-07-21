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
  /// 默认宽松，因 native 侧已自带 20s no-progress watchdog。
  final Duration initTimeout;

  /// Android 上绕过 ExoPlayer 直接走 IJK（紧急覆盖 / A/B 用）。
  /// iOS 和 Web 忽略本标志。
  final bool forceIjkOnAndroid;

  /// Android 上把视频渲染从 Flutter Texture 切到 PlatformView（SurfaceView
  /// 原生缩放），画质上限更高。默认 false（opt-in）；iOS / Web 忽略。
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
  /// wasPlaying）。默认 `true`：回滚成功不 rethrow，回滚也失败才
  /// emit [LineSwitchFailed] 并 rethrow。与 [autoFailoverOnInitialError] 独立。
  final bool rollbackOnSwitchFailure;

  /// 默认线路首次 initialize 失败时，是否自动按 priority 升序遍历其余线路。
  /// 默认 `true`：全失败才抛最后一条错误 → `PlayerPhase.error`。
  /// 单线路场景本 flag 无效。
  final bool autoFailoverOnInitialError;
}
