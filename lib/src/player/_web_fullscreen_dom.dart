// 浏览器全屏 DOM 原语的非 web 空实现。web 实现见 _web_fullscreen_dom_web.dart；
// web_fullscreen_coordination.dart 用条件导入在 web 上换成 web 版。
//
// 这些都是「页面级」浏览器全屏操作（对整个 Flutter 画布全屏 / 查能力 / 监听
// 状态），与具体 video 元素无关，故不放在 backend 而放全屏协调层。
library;

/// 浏览器是否支持对任意 element 全屏（iOS Safari 返 false，只支持 `<video>`
/// 元素级全屏）。非 web 永远 false。
bool supportsElementFullscreen() => false;

/// 对整个 Flutter 画布（documentElement）进入浏览器真全屏。非 web 为空操作。
Future<void> requestBrowserFullscreen() async {}

/// 退出浏览器真全屏。非 web 为空操作。
Future<void> exitBrowserFullscreen() async {}

/// 监听浏览器全屏状态变化（含用户按 ESC），返回反注册函数。非 web 为空操作。
void Function() onBrowserFullscreenChange(void Function(bool isFullscreen) cb) =>
    () {};
