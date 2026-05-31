/// Conditional re-export：web 走 `default_backend_factory_web.dart`
/// （用 [WebVideoBackend]），iOS / Android 走 `default_backend_factory_io.dart`
/// （用 [VideoPlayerBackend] / [NativeBackend]）。
///
/// 这种模式让 `package:web` / `dart:ui_web` web-only library 完全隔离在
/// `*_web.dart` 文件内，不污染 io 平台编译。
///
/// 条件键用 `dart.library.js_interop`（不是 `dart.library.html`）——后者在
/// `flutter build web --wasm` 下为 false，会把 web 误路由到 io 后端。
library;

export 'default_backend_factory_io.dart'
    if (dart.library.js_interop) 'default_backend_factory_web.dart';
