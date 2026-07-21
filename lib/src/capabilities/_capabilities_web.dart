import 'package:web/web.dart' as web;

/// 设备媒体能力探测（web 实现）。
class NiumaCapabilities {
  NiumaCapabilities._();

  static bool? _hevcCache;

  /// 浏览器是否能播 H.265——`MediaSource.isTypeSupported`（MSE/hls.js 路径）
  /// 与 `<video>.canPlayType`（Safari 原生）取或，探测串 `hvc1.1.6.L93.B0`。
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
