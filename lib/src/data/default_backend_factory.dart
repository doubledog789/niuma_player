import '../domain/backend_factory.dart';
import '../domain/data_source.dart';
import '../domain/player_backend.dart';
import 'ijk_backend.dart';
import 'video_player_backend.dart';

/// Production implementation — constructs real video_player / IJK backends.
class DefaultBackendFactory implements BackendFactory {
  const DefaultBackendFactory();

  @override
  PlayerBackend createVideoPlayer(NiumaDataSource ds) =>
      VideoPlayerBackend(ds);

  @override
  PlayerBackend createIjk(NiumaDataSource ds) => IjkBackend(ds);
}
