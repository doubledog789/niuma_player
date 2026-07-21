import 'package:flutter/foundation.dart' show ValueListenable;

import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_state.dart';

/// 当前驱动 [NiumaPlayerController] 的 Dart 侧 backend 类型。
/// `native` 覆盖 ExoPlayer 和 IJK——子变体由 Android 插件内部选择。
enum PlayerBackendKind {
  /// `package:video_player`。iOS（AVPlayer）和 Web（`<video>`）使用。
  videoPlayer,

  /// niuma_player 自家 native 插件（Android）。ExoPlayer / IJK 的选择
  /// 对 Dart 侧不透明，可经 `selectedVariant` 感知。
  native,
}

/// 每个 backend（video_player / IJK / 测试替身）都必须实现的内部契约。
/// [NiumaPlayerController] 针对该抽象编写，因此回退就只是 dispose 一个
/// 实例、构造另一个。
abstract class PlayerBackend {
  /// 标识本 backend 的类型。视图和事件中会用到。
  PlayerBackendKind get kind;

  /// native texture id；如果 backend 不暴露 texture（例如 iOS 上的
  /// video_player 用自己的 widget）则为 null。
  int? get textureId;

  /// Android PlatformView 模式下的 session instance id；非 null 时
  /// `NiumaPlayerView` 用 `AndroidView` 渲染。默认 null。
  int? get androidPlatformViewId => null;

  /// Web-only：HtmlElementView 注册的 viewType，非 null 时
  /// `NiumaPlayerView` 用 `HtmlElementView` 渲染。默认 null。
  String? get htmlViewType {
    return null;
  }

  /// Web-only：fullscreen 状态，NiumaPlayerView 据此选 inline / overlay
  /// 渲染。默认 null，只有 [WebVideoBackend] 重写。
  ValueListenable<bool>? get webFullscreenState => null;

  /// Web-only：让底层 `<video>` 进浏览器原生全屏。默认返 false。
  /// iOS Safari 只能走 `webkitEnterFullscreen`（进系统 player，Flutter
  /// 控件不跟随）；其余浏览器走标准 `requestFullscreen()`。
  Future<bool> enterNativeFullscreen() async => false;

  /// Web-only：退出浏览器原生 fullscreen。默认实现返 false。
  Future<bool> exitNativeFullscreen() async => false;

  /// 当前状态快照。与 [valueStream] 同步更新。
  NiumaPlayerValue get value;

  /// 状态快照流。订阅时为方便起见必须立即发出当前值
  /// （实现应使用 broadcast + replay-latest）。
  Stream<NiumaPlayerValue> get valueStream;

  /// backend 级事件（目前只有错误；像 `BackendSelected` 这种 controller
  /// 级事件挂在 controller 上，不放这里）。
  Stream<NiumaPlayerEvent> get eventStream;

  Future<void> initialize();

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  Future<void> setSpeed(double speed);

  Future<void> setVolume(double volume);

  Future<void> setLooping(bool looping);

  /// 是否支持原地换源（复用底层播放器不重建）。默认 false；web 为 true——
  /// 复用 `<video>` 元素保住 iOS Safari 的「有声播放激活」。
  bool get supportsSourceSwap => false;

  /// 原地换到新数据源 [source]，复用当前底层播放器。仅 [supportsSourceSwap]
  /// 为 true 时有意义；默认抛 [UnsupportedError]，由上层改走 dispose + 重建。
  Future<void> load(NiumaDataSource source) async =>
      throw UnsupportedError('backend does not support in-place source swap');

  /// Web-only：开 / 关 `<video>` 浏览器原生控件。非 web 为空操作。
  /// iOS Safari 会吞视频像素区的点击导致自定义控件失效，可开原生控件兜底。
  Future<void> setWebNativeControls(bool show) async {}

  /// 读当前亮度（窗口级 0..1，未支持返 0）。
  Future<double> getBrightness() async => 0.0;

  /// 设置窗口亮度（0..1）。失败 / 不支持返 false。
  Future<bool> setBrightness(double value) async => false;

  /// 读当前系统媒体音量 0..1。
  Future<double> getSystemVolume() async => 0.0;

  /// 设置系统媒体音量（0..1）。失败 / 不支持返 false。
  Future<bool> setSystemVolume(double value) async => false;

  /// 进入 PiP。[aspectNum]/[aspectDen] 为宽高比；失败 / 不支持返 false
  /// （默认实现）。[unsafeAutoBackground] 仅 iOS：调私有 API 模拟 home 键
  /// 让小窗立刻飘出，**会让 host app 失去上 App Store 资格**。
  Future<bool> enterPictureInPicture({
    required int aspectNum,
    required int aspectDen,
    bool unsafeAutoBackground = false,
  }) async =>
      false;

  /// 退出 PiP。不在 PiP 是 no-op，返回 false。默认实现返 false。
  Future<bool> exitPictureInPicture() async => false;

  /// 查询当前设备 + 视频是否支持 PiP。默认返 false。
  Future<bool> queryPictureInPictureSupport() async => false;

  /// 更新 PiP 窗播放/暂停 RemoteAction 图标——仅 Android 需要，
  /// iOS 由 AVKit 自动同步。默认 no-op。
  Future<void> updatePictureInPictureActions({required bool isPlaying}) async {}

  Future<void> dispose();
}
