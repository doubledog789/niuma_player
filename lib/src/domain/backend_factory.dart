import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_backend.dart';

/// 对具体 backend 构造的间接层，使测试可以注入 fake，无需 stub
/// `dart:io` Platform / native channels。生产实现在
/// `data/default_backend_factory.dart`。
abstract class BackendFactory {
  /// 构造 video_player 会话（iOS / Web）。
  PlayerBackend createVideoPlayer(NiumaDataSource ds);

  /// 构造 niuma native 会话（仅 Android）。[forceIjk] 为 true 直接用 IJK；
  /// [useAndroidPlatformView] 为 true 走 PlatformView（`SurfaceView`）路径。
  PlayerBackend createNative(
    NiumaDataSource ds, {
    required bool forceIjk,
    bool useAndroidPlatformView = false,
  });
}
