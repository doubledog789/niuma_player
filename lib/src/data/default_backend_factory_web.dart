import 'package:niuma_player/src/data/web_video_backend.dart';
import 'package:niuma_player/src/domain/backend_factory.dart';
import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_backend.dart';

/// Web 平台 BackendFactory——iOS / Android 走 `default_backend_factory_io.dart`，
/// 通过 `default_backend_factory.dart` 的 conditional import 切。
///
/// web 端不再用 `package:video_player` 的 web 实现（single-instance + tap
/// 拦截 + 黑屏 bug）——直接用自家 [WebVideoBackend]（`<video>` HTML element
/// + `ui_web` platform view）。
class DefaultBackendFactory implements BackendFactory {
  const DefaultBackendFactory();

  @override
  PlayerBackend createVideoPlayer(NiumaDataSource ds) => WebVideoBackend(ds);

  /// Web 平台不存在 niuma 自家 native 插件——`createNative` 返一个
  /// [WebVideoBackend] 兜底（实际 controller 选择路径在 web 永远走
  /// `createVideoPlayer`，这条不会被调，但保接口完整性）。
  @override
  PlayerBackend createNative(NiumaDataSource ds, {required bool forceIjk}) =>
      WebVideoBackend(ds);
}
