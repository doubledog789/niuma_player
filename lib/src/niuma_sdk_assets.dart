/// niuma_player SDK 运行时资源常量。
///
/// headless 核只保留 web 后端运行时需要的 vendored hls.js 路径；UI 资源
/// （loading 动画 / 控件图标 / 进度条牛马表情）已移出核，由消费方 app 自带。
class NiumaSdkAssets {
  NiumaSdkAssets._();

  static const String _pkg = 'niuma_player';

  /// Web-only：vendored hls.js（HLS-in-Chrome）的 **HTTP 运行时 URL**——
  /// 注意不是 `rootBundle` 的 asset key（那个是 `packages/$_pkg/...`），
  /// 而是 flutter web 构建后 package asset 对外暴露的 `assets/packages/...`
  /// 路径，供 [WebVideoBackend] 动态注入 `<script src>` 用。
  static const String hlsJsUrl =
      'assets/packages/$_pkg/assets/hls/hls.min.js';
}
