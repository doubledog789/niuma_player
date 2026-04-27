import 'data_source.dart';
import 'player_backend.dart';

/// Indirection over concrete backend construction so tests can inject fakes
/// without stubbing `dart:io` Platform / native channels. Production
/// implementation lives in `data/default_backend_factory.dart`.
abstract class BackendFactory {
  /// Build a `package:video_player`-backed session. Used on iOS (AVPlayer)
  /// and Web (`<video>` + hls.js via video_player_web_hls).
  PlayerBackend createVideoPlayer(NiumaDataSource ds);

  /// Build a niuma_player native session (Android only). When [forceIjk] is
  /// true, the native side is asked to use IJK directly without trying
  /// ExoPlayer first; otherwise native consults its own `DeviceMemoryStore`
  /// and falls through to ExoPlayer.
  PlayerBackend createNative(NiumaDataSource ds, {required bool forceIjk});
}
