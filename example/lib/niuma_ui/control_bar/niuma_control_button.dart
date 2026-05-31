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
}
