/// SDK 内置原子按钮枚举，用于 [NiumaControlBarConfig] 声明式配置控件区域。
///
/// 不含 episode/next/previous——SDK 不引入 playlist 概念，业务通过
/// [NiumaPlayer.bottomActionsBuilder] slot 自塞。
enum NiumaControlButton {
  back,
  title,
  cast,
  pip,
  lineSwitch,
  more,
  playPause,
  speed,
  danmakuToggle,
  danmakuInput,
  subtitle,
  volume,
  fullscreen,
  timeDisplay,
  scrubBar,
  /// 锁屏按钮（全屏专用）。点击切 ic_lock ↔ ic_unlock，业务可通过 SDK
  /// 顶层 [NiumaPlayerController.lockNotifier] 监听锁状态来 freeze 其它控件。
  lock,
  /// 设置入口（全屏专用，比 [more] 更显式的齿轮 icon）。点击调用宿主
  /// 注入的 onSettings 回调。
  settings,
}
