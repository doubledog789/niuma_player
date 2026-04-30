import 'data_source.dart';
import 'player_backend.dart';

/// 对具体 backend 构造的间接层，使测试可以注入 fake，无需 stub
/// `dart:io` Platform / native channels。生产实现在
/// `data/default_backend_factory.dart`。
abstract class BackendFactory {
  /// 构造一个由 `package:video_player` 支撑的会话。iOS（AVPlayer）和
  /// Web（`<video>` + 经 video_player_web_hls 的 hls.js）使用。
  PlayerBackend createVideoPlayer(NiumaDataSource ds);

  /// 构造一个 niuma_player native 会话（仅 Android）。[forceIjk] 为
  /// true 时要求 native 侧直接用 IJK，不先尝试 ExoPlayer；否则 native
  /// 自查 `DeviceMemoryStore` 并落到 ExoPlayer。
  PlayerBackend createNative(NiumaDataSource ds, {required bool forceIjk});
}
