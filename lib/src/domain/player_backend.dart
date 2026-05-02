import 'player_state.dart';

/// 当前驱动 [NiumaPlayerController] 的 Dart 侧 backend 是哪个。
///
/// 注意 `native` 覆盖 ExoPlayer 和 IJK——那是 Android 插件*内部*选择的
/// 子变体，本层看不到。需要这层细节请看
/// `NiumaPlayerValue.openingStage` / 事件日志。
enum PlayerBackendKind {
  /// `package:video_player`。iOS（AVPlayer）和 Web（`<video>`）使用。
  videoPlayer,

  /// niuma_player 自己的 native 插件。Android 使用。内部在 ExoPlayer
  /// （默认快路径）和 IJK（软解兜底）之间选择；从 Dart 侧看是不透明的，
  /// 只能通过 backend 实现上的 `selectedVariant` 字段（经由
  /// [BackendSelected.fromMemory] 事件抛出供 app 级日志）感知。
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

  /// 读当前亮度（窗口级 0..1，未支持返 0）。
  Future<double> getBrightness() async => 0.0;

  /// 设置窗口亮度（0..1）。失败 / 不支持返 false。
  Future<bool> setBrightness(double value) async => false;

  /// 读当前系统媒体音量 0..1。
  Future<double> getSystemVolume() async => 0.0;

  /// 设置系统媒体音量（0..1）。失败 / 不支持返 false。
  Future<bool> setSystemVolume(double value) async => false;

  /// 进入 PiP（画中画）。
  ///
  /// [aspectNum] / [aspectDen] 是 video aspect 的整数表达
  /// （Android 端 PictureInPictureParams 要求 Rational）。
  /// 不支持 / 失败返回 false。
  ///
  /// 默认实现返 false——backend 不支持 PiP（如 IJK、Mock）时**无需**重写
  /// 此方法即为正确行为。VideoPlayerBackend / NativeBackend 应重写。
  Future<bool> enterPictureInPicture({
    required int aspectNum,
    required int aspectDen,
  }) async => false;

  /// 退出 PiP。不在 PiP 是 no-op，返回 false。默认实现返 false。
  Future<bool> exitPictureInPicture() async => false;

  /// 查询当前设备 + 视频是否支持 PiP。默认返 false。
  Future<bool> queryPictureInPictureSupport() async => false;

  Future<void> dispose();
}
