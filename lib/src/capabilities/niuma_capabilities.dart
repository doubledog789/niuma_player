/// Conditional re-export：设备媒体能力探测，web 走 `_web`、io 走 `_io`。
/// 条件键必须用 `dart.library.js_interop`（`dart.library.html` 在
/// `--wasm` 下为 false，会误路由到 io 实现）。
library;

export '_capabilities_io.dart'
    if (dart.library.js_interop) '_capabilities_web.dart';
