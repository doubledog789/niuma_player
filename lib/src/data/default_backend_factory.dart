import '../domain/backend_factory.dart';
import '../domain/data_source.dart';
import '../domain/player_backend.dart';
import 'native_backend.dart';
import 'video_player_backend.dart';

/// Production implementation — constructs real video_player / niuma native
/// backends.
class DefaultBackendFactory implements BackendFactory {
  const DefaultBackendFactory();

  @override
  PlayerBackend createVideoPlayer(NiumaDataSource ds) =>
      VideoPlayerBackend(ds);

  @override
  PlayerBackend createNative(NiumaDataSource ds, {required bool forceIjk}) =>
      NativeBackend(ds, forceIjk: forceIjk);
}
