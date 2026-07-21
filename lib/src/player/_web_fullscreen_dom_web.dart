import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// 浏览器是否支持对任意 element 全屏。
/// 必须用 getProperty 安全读：iOS Safari 上 `fullscreenEnabled` 是 undefined，
/// 直接按 package:web 的非空 bool 读会抛 TypeError；undefined/null 一律当 false。
bool supportsElementFullscreen() =>
    (web.document as JSObject)
        .getProperty<JSBoolean?>('fullscreenEnabled'.toJS)
        ?.toDart ??
    false;

/// 对 `documentElement`（整个 Flutter 画布）进入浏览器真全屏。
/// 必须在用户手势栈内调用，否则浏览器以「缺少用户激活」拒绝；失败静默。
Future<void> requestBrowserFullscreen() async {
  final el = web.document.documentElement;
  if (el == null) return;
  try {
    await el.requestFullscreen().toDart;
  } catch (_) {/* 缺用户激活 / 不支持：忽略 */}
}

Future<void> exitBrowserFullscreen() async {
  try {
    if (web.document.fullscreenElement != null) {
      await web.document.exitFullscreen().toDart;
    }
  } catch (_) {/* 已不在全屏：忽略 */}
}

/// 监听 `fullscreenchange`（含 ESC 退出），返回反注册函数。
void Function() onBrowserFullscreenChange(void Function(bool) cb) {
  late final JSFunction listener;
  listener = ((web.Event _) => cb(web.document.fullscreenElement != null)).toJS;
  web.document.addEventListener('fullscreenchange', listener);
  return () => web.document.removeEventListener('fullscreenchange', listener);
}
