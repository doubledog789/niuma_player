import 'package:niuma_player/src/domain/backend_factory.dart';
import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_backend.dart';
import 'package:niuma_player/src/data/native_backend.dart';
import 'package:niuma_player/src/data/video_player_backend.dart';

/// 生产实现——构造真实的 video_player / niuma native 后端。
class DefaultBackendFactory implements BackendFactory {
  const DefaultBackendFactory();

  @override
  PlayerBackend createVideoPlayer(NiumaDataSource ds) =>
      VideoPlayerBackend(ds);

  @override
  PlayerBackend createNative(NiumaDataSource ds, {required bool forceIjk}) =>
      NativeBackend(ds, forceIjk: forceIjk);
}
