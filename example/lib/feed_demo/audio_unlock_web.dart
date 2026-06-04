import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// web：监听 document 的首次 `pointerdown` 后触发 [callback]，随即反注册。
///
/// 用 **capture 阶段**（addEventListener 第三参 `true`）是关键：feed 的
/// `<video>` platform-view 容器会吞掉落在视频像素区的 pointer 事件，普通冒泡
/// 监听可能收不到；capture 阶段在事件下行时先于任何 target 拿到，必中。
///
/// 用途：浏览器禁止带声音的自动播放，feed 先静音自动播，靠这个首次手势把音频
/// 解锁（在事件回调栈内取消静音，满足浏览器的用户激活要求）。
void onFirstUserGesture(void Function() callback) {
  late final JSFunction listener;
  listener = ((web.Event _) {
    callback();
    web.document.removeEventListener('pointerdown', listener, true.toJS);
  }).toJS;
  web.document.addEventListener('pointerdown', listener, true.toJS);
}

/// web：监听 **每次** `pointerdown`（capture 阶段，同样为了穿过 platform-view
/// 吞噬），返回反注册函数。iOS Safari 用：每次点屏幕都在手势同步栈内 unmute
/// 当前页（WebKit 不发 sticky 激活，带声音播放每次都要现挣手势）。
void Function() onEveryUserTap(void Function() callback) {
  late final JSFunction listener;
  listener = ((web.Event _) => callback()).toJS;
  web.document.addEventListener('pointerdown', listener, true.toJS);
  return () =>
      web.document.removeEventListener('pointerdown', listener, true.toJS);
}
