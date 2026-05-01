/// 视频手势类型枚举。
enum GestureKind {
  /// 双击切换播放 / 暂停。
  doubleTap,

  /// 水平滑动调节进度。
  horizontalSeek,

  /// 左半屏垂直滑动调节亮度（窗口级，非系统级）。
  brightness,

  /// 右半屏垂直滑动调节音量（系统媒体音量）。
  volume,

  /// 长按视频区临时 2x 倍速，松手恢复原速度。
  longPressSpeed,
}
