import 'data_source.dart';
import 'player_backend.dart';

/// Indirection over concrete backend construction so tests can inject fakes
/// without stubbing `dart:io` Platform / native channels. Production
/// implementation lives in `data/default_backend_factory.dart`.
abstract class BackendFactory {
  PlayerBackend createVideoPlayer(NiumaDataSource ds);
  PlayerBackend createIjk(NiumaDataSource ds);
}
