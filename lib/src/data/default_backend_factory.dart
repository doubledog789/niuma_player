/// Conditional re-export：web 走 `_web`，iOS / Android 走 `_io`，隔离
/// web-only library。条件键必须用 `dart.library.js_interop`——
/// `dart.library.html` 在 `--wasm` 下为 false，会把 web 误路由到 io 后端。
library;

export 'default_backend_factory_io.dart'
    if (dart.library.js_interop) 'default_backend_factory_web.dart';
