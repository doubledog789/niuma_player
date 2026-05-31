import 'package:web/web.dart' as web;

/// 把 `<body>` 与 `<html>` 的 `background-color` 改为给定 CSS 色值，
/// 传 `null` 还原成默认（清空 inline style）。
///
/// 用途：iOS Safari PWA 模式进全屏时，视频与 viewport 的 aspect ratio
/// 错位会让"空地"露出 host 页面默认白底——很突兀。进 fullscreen 路由
/// 时把根背景刷黑，dispose 时恢复。
///
/// 仅 web 平台会真正执行；其它平台是 stub no-op（见 `_root_bg_io.dart`）。
void setWebRootBackground(String? cssColor) {
  web.document.body?.style.backgroundColor = cssColor ?? '';
  (web.document.documentElement as web.HTMLElement?)?.style.backgroundColor =
      cssColor ?? '';
}
