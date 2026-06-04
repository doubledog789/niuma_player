/// 纯函数 HLS 判定——抽出来不依赖 web-only library，可在 VM 单测里跑
/// （[WebVideoBackend] 整文件 import `package:web` / `dart:ui_web`，无法
/// 在 VM 里 import）。
///
/// 仅做 URL 后缀判断；浏览器是否原生支持 HLS（Safari 支持、Chrome/Firefox
/// 不支持）由调用方叠加 `<video>.canPlayType` 判定。
library;

/// URL（去掉 query / fragment 后）是否以 `.m3u8` 结尾，大小写不敏感。
bool isHlsUrl(String uri) {
  final q = uri.indexOf('?');
  final h = uri.indexOf('#');
  var end = uri.length;
  if (q >= 0) end = q;
  if (h >= 0 && h < end) end = h;
  return uri.substring(0, end).toLowerCase().endsWith('.m3u8');
}
