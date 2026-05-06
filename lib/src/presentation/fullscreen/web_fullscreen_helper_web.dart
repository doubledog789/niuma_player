/// Web 平台 fullscreen 实现——用浏览器原生 `requestFullscreen()` /
/// `exitFullscreen()` 让整个 Flutter document 进入全屏。**不**通过
/// `Navigator.push` 创建 NiumaFullscreenPage——web 上单 video element
/// 多 widget 引用会黑屏。
library;

// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool isWebFullscreenAvailable() {
  // documentElement 必有；fullscreenEnabled 部分浏览器叫 webkitFullscreenEnabled
  // 取保险默认 true（fullscreenEnabled 在 iframe 内可能 false）。
  return html.document.documentElement != null;
}

Future<bool> enterWebFullscreen() async {
  final el = html.document.documentElement;
  if (el == null) return false;
  try {
    await el.requestFullscreen();
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> exitWebFullscreen() async {
  if (html.document.fullscreenElement == null) return false;
  try {
    html.document.exitFullscreen();
    return true;
  } catch (_) {
    return false;
  }
}

bool isInWebFullscreen() => html.document.fullscreenElement != null;
