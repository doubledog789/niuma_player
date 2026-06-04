// 非 web 平台的空实现——原生端本就有声音，无需「首次手势解锁音频」。
//
// web 实现见 audio_unlock_web.dart：浏览器禁止带声音的自动播放，feed 只能
// 先静音自动播，等用户首次与页面交互后再解除静音。feed_page.dart 用条件导入
// 在 web 上换成 web 版。
library;

/// 注册一次性回调：用户首次与页面交互时触发（仅 web 有意义；非 web 为空操作）。
void onFirstUserGesture(void Function() callback) {}

/// 注册「每次」用户点击回调（持续，不反注册），返回反注册函数。iOS Safari 用：
/// 每次点屏幕在手势同步栈内 unmute 当前页（带声音播放须在手势栈内）。非 web
/// 为空操作。
void Function() onEveryUserTap(void Function() callback) => () {};
