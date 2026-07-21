/// Conditional re-export：设备媒体能力探测。
///
/// web 走 `_capabilities_web.dart`（`MediaSource.isTypeSupported` +
/// `<video>.canPlayType`），iOS / Android 走 `_capabilities_io.dart`
/// （iOS 系统级支持；Android 查 `MediaCodecList` 硬解）。
///
/// 条件键用 `dart.library.js_interop`（不是 `dart.library.html`）——后者在
/// `flutter build web --wasm` 下为 false，会把 web 误路由到 io 实现。
library;

export '_capabilities_io.dart'
    if (dart.library.js_interop) '_capabilities_web.dart';
