/// Conditional re-export：web 走 `default_backend_factory_web.dart`
/// （用 [WebVideoBackend]），iOS / Android 走 `default_backend_factory_io.dart`
/// （用 [VideoPlayerBackend] / [NativeBackend]）。
///
/// 这种模式让 `dart:html` / `dart:ui_web` web-only library 完全隔离在
/// `*_web.dart` 文件内，不污染 io 平台编译。
library;

export 'default_backend_factory_io.dart'
    if (dart.library.html) 'default_backend_factory_web.dart';
