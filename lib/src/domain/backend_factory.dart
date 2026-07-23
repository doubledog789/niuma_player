import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_backend.dart';

/// 对具体 backend 构造的间接层，使测试可以注入 fake，无需 stub
/// `dart:io` Platform / native channels。生产实现在
/// `data/default_backend_factory.dart`。
abstract class BackendFactory {
  /// 构造 video_player 会话（三端主路径）。[useAndroidPlatformView] 为 true
  /// 时 Android 侧映射为 vp 的 `VideoViewType.platformView`（其余平台忽略）。
  PlayerBackend createVideoPlayer(
    NiumaDataSource ds, {
    bool useAndroidPlatformView = false,
  });

  /// 构造 niuma native 会话（Android IJK 软解兜底）。
  /// [useAndroidPlatformView] 为 true 走 PlatformView（`SurfaceView`）路径。
  PlayerBackend createNative(
    NiumaDataSource ds, {
    bool useAndroidPlatformView = false,
  });
}
