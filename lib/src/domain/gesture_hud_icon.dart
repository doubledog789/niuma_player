/// 手势 HUD 的语义图标——headless 核只产出"是什么意图"，不绑定具体资源路径。
///
/// 由消费方 HUD widget 映射到自己的 icon 资源（SVG / [IconData] / 等）。
enum GestureHudIcon {
  /// 播放。
  play,

  /// 暂停。
  pause,

  /// 倍速。
  speed,

  /// 快进。
  seekForward,

  /// 快退。
  seekBackward,

  /// 亮度。
  brightness,

  /// 音量。
  volume,

  /// 静音（音量为 0）。
  volumeMute,
}
