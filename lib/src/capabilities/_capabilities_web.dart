import 'package:web/web.dart' as web;

/// 设备媒体能力探测（web 实现）。
class NiumaCapabilities {
  NiumaCapabilities._();

  static bool? _hevcCache;

  /// 浏览器是否能播 H.265 / HEVC。
  ///
  /// 两路取或：
  /// - `MediaSource.isTypeSupported`——hls.js（MSE）路径的硬前提
  ///   （Chrome 107+ 在设备有硬解时支持）；
  /// - `<video>.canPlayType`——Safari 原生 HLS / 直链 mp4 路径。
  ///
  /// codec 串用 `hvc1.1.6.L93.B0`（Main profile L3.1，最普遍的兼容探测串）。
  static Future<bool> supportsHevc() async {
    final cached = _hevcCache;
    if (cached != null) return cached;
    const mime = 'video/mp4; codecs="hvc1.1.6.L93.B0"';
    var ok = false;
    try {
      ok = web.MediaSource.isTypeSupported(mime);
    } catch (_) {
      // 某些环境（老 WebKit）没有 MediaSource——继续走 canPlayType。
    }
    if (!ok) {
      try {
        final video =
            web.document.createElement('video') as web.HTMLVideoElement;
        ok = video.canPlayType(mime).isNotEmpty;
      } catch (_) {}
    }
    return _hevcCache = ok;
  }
}
