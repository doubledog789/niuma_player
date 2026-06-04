import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// **必须用 getProperty 安全读**：iOS Safari 的 `document.fullscreenEnabled` 是
/// `undefined`（不支持标准 Fullscreen API），而 package:web 把它声明成非空
/// `bool`，直接读会抛 `TypeError: null is not a subtype of bool`。这里把
/// undefined / null 一律当 `false`（iOS Safari 即归此类）。
bool supportsElementFullscreen() =>
    (web.document as JSObject)
        .getProperty<JSBoolean?>('fullscreenEnabled'.toJS)
        ?.toDart ??
    false;

/// 对 `documentElement`（整个 Flutter 画布）进入浏览器真全屏。
///
/// **必须在用户手势栈内调用**（点全屏按钮的同步路径里），否则浏览器以
/// 「缺少用户激活」拒绝。失败时静默——上层 push 的全屏页仍会占满视口。
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

/// 监听 `fullscreenchange`（含用户按 ESC 退出浏览器全屏），回调当前是否全屏。
/// 返回反注册函数，调用方在 dispose 时务必调用。
void Function() onBrowserFullscreenChange(void Function(bool) cb) {
  late final JSFunction listener;
  listener = ((web.Event _) => cb(web.document.fullscreenElement != null)).toJS;
  web.document.addEventListener('fullscreenchange', listener);
  return () => web.document.removeEventListener('fullscreenchange', listener);
}
