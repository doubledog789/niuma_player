/// io 平台 stub——web 实际实现在 web_fullscreen_helper_web.dart，由
/// web_fullscreen_helper.dart 用 conditional import 切换。
///
/// io 平台调这俩函数返 false——业务方应该走 NiumaFullscreenPage 路径。
library;

bool isWebFullscreenAvailable() => false;

Future<bool> enterWebFullscreen() async => false;

Future<bool> exitWebFullscreen() async => false;

bool isInWebFullscreen() => false;
