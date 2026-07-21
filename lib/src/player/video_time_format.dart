/// 把 [Duration] 格式化成 "mm:ss" 或 "H:mm:ss"（小时数 ≥ 1 时）。
String formatVideoTime(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}
