// 浏览器全屏 DOM 原语的非 web 空实现；web 版见 _web_fullscreen_dom_web.dart，
// 由 web_fullscreen_coordination.dart 条件导入切换。
library;

/// 浏览器是否支持对任意 element 全屏。非 web 永远 false。
bool supportsElementFullscreen() => false;

/// 对整个 Flutter 画布进入浏览器真全屏。非 web 为空操作。
Future<void> requestBrowserFullscreen() async {}

/// 退出浏览器真全屏。非 web 为空操作。
Future<void> exitBrowserFullscreen() async {}

/// 监听浏览器全屏状态变化，返回反注册函数。非 web 为空操作。
void Function() onBrowserFullscreenChange(void Function(bool isFullscreen) cb) =>
    () {};
