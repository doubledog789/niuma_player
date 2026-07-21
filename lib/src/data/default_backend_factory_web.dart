import 'package:niuma_player/src/data/web_video_backend.dart';
import 'package:niuma_player/src/domain/backend_factory.dart';
import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_backend.dart';

/// Web 平台 BackendFactory——用自家 [WebVideoBackend]，不用
/// `package:video_player` 的 web 实现（single-instance + tap 拦截 + 黑屏 bug）。
class DefaultBackendFactory implements BackendFactory {
  const DefaultBackendFactory();

  @override
  PlayerBackend createVideoPlayer(NiumaDataSource ds) => WebVideoBackend(ds);

  /// Web 无 native 插件——返 [WebVideoBackend] 兜底，仅保接口完整性。
  @override
  PlayerBackend createNative(
    NiumaDataSource ds, {
    required bool forceIjk,
    bool useAndroidPlatformView = false,
  }) =>
      WebVideoBackend(ds);
}
