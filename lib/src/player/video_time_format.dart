/// 把 [Duration] 格式化成 "mm:ss" 或 "H:mm:ss"（小时数 ≥ 1 时）。
///
/// niuma_player 内部多处使用相同时间格式（手势 HUD seek、短视频 scrub
/// label 等），统一在此函数实现，避免拷贝。
String formatVideoTime(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}
