import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, kIsWeb;
import 'package:flutter/widgets.dart';

import '_web_fullscreen_dom.dart'
    if (dart.library.js_interop) '_web_fullscreen_dom_web.dart' as dom;

/// 当前 web 浏览器的全屏策略——接入方据此分流全屏 UI。
enum NiumaWebFullscreenMode {
  /// 非 web 平台（Android / iOS 原生 App）。
  notWeb,

  /// iOS Safari 等：只支持 `<video>` 元素级全屏（进系统原生 player、
  /// 不保留 Flutter 控件）。走 `NiumaPlayerController.enterNativeFullscreen()`。
  nativeVideoElement,

  /// Chrome / Firefox / 桌面 Safari 等：支持对画布 Element 全屏，可保留
  /// Flutter 控件。走 [requestBrowserFullscreen] + 自己的全屏 UI。
  browserElement,
}

/// 当前 web 浏览器的全屏策略（见 [NiumaWebFullscreenMode]）。
/// DOM 能力检测收在核里，接入方直接据此分流全屏 UI。
NiumaWebFullscreenMode get webFullscreenMode {
  if (!kIsWeb) return NiumaWebFullscreenMode.notWeb;
  return dom.supportsElementFullscreen()
      ? NiumaWebFullscreenMode.browserElement
      : NiumaWebFullscreenMode.nativeVideoElement;
}

/// 对整个 Flutter 画布进入浏览器真全屏（仅 web）。
/// 必须在用户手势栈内同步调用，否则浏览器以「缺少用户激活」拒绝。
Future<void> requestBrowserFullscreen() => dom.requestBrowserFullscreen();

/// 退出浏览器真全屏（仅 web）。
Future<void> exitBrowserFullscreen() => dom.exitBrowserFullscreen();

/// 监听浏览器全屏状态变化（含 ESC 退出），返回反注册函数；dispose 时务必
/// 调用反注册。仅 web 有意义。
void Function() onBrowserFullscreenChange(void Function(bool isFullscreen) cb) =>
    dom.onBrowserFullscreenChange(cb);

/// Web 全屏路由计数：inline [NiumaPlayerView] 监听它，>0 时不挂
/// HtmlElementView，让单个 `<video>` 留在全屏那侧的容器里。
/// 必须是进程级计数而非 backend 自家状态——line failover 换 backend 时
/// 状态会被重置，inline 会误判退出全屏抢回 `<video>` 导致全屏侧黑屏。
final ValueNotifier<int> _webFullscreenRouteCount = ValueNotifier<int>(0);

/// [_webFullscreenRouteCount] 的只读视图；写侧只走 enter / exit 协调 API。
ValueListenable<int> get webFullscreenRouteCountListenable =>
    _webFullscreenRouteCount;

/// 进入一个 web 全屏路由：计数 +1。全屏页 push 时调一次。
void enterWebFullscreenRoute() {
  _webFullscreenRouteCount.value = _webFullscreenRouteCount.value + 1;
}

/// 退出一个 web 全屏路由：计数 -1（下限 0）。全屏页 pop 时调一次。
void exitWebFullscreenRoute() {
  if (_webFullscreenRouteCount.value > 0) {
    _webFullscreenRouteCount.value = _webFullscreenRouteCount.value - 1;
  }
}

/// 标记"此 subtree 处于全屏路由内"的 [InheritedWidget] marker。
/// [NiumaPlayerView] 用 [maybeOf] 判断自己是 inline 还是全屏那份，
/// 决定把 `HtmlElementView` 挂哪边（web 单 `<video>` 不能两处 mount）。
class NiumaFullscreenScope extends InheritedWidget {
  /// 构造一个 marker scope。
  const NiumaFullscreenScope({super.key, required super.child});

  /// 找最近的 [NiumaFullscreenScope]——存在即返回非空 marker。
  static NiumaFullscreenScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<NiumaFullscreenScope>();
  }

  @override
  bool updateShouldNotify(NiumaFullscreenScope oldWidget) => false;
}
