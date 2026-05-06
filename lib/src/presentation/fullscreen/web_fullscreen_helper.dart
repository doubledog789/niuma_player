/// Conditional re-export：web 用浏览器原生 `requestFullscreen()`，io 平台
/// stub 返 false（业务方仍走 NiumaFullscreenPage 路径）。
///
/// 用途：`NiumaFullscreenButton` / `NiumaShortVideoFullscreenButton` 在
/// web 上检测 [isWebFullscreenAvailable] 时改调 [enterWebFullscreen] /
/// [exitWebFullscreen]——避免 push fullscreen route 导致 web 上单
/// `<video>` element 多 widget 引用 黑屏 bug。
library;

export 'web_fullscreen_helper_io.dart'
    if (dart.library.html) 'web_fullscreen_helper_web.dart';
