import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../data/video_player_backend.dart';
import '../domain/player_backend.dart';
import '../domain/player_state.dart';
import 'niuma_player_controller.dart';

/// 渲染 [NiumaPlayerController] 当前激活的 backend。
///
/// backend 切换（例如回退到 IJK）时自动 rebuild，调用方直接把它丢
/// 进 widget tree 即可。
class NiumaPlayerView extends StatelessWidget {
  const NiumaPlayerView(this.controller, {super.key, this.aspectRatio});

  final NiumaPlayerController controller;

  /// 为 null 时回落到 `controller.value.size`。两者都不可用时渲染
  /// 16:9 占位框以保持布局稳定。
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NiumaPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final backend = controller.backend;
        final ratio = aspectRatio ?? _ratioFromValue(value);
        final Widget child;
        if (backend is VideoPlayerBackend) {
          child = VideoPlayer(backend.innerController);
        } else if (backend != null &&
            backend.kind == PlayerBackendKind.native &&
            controller.textureId != null) {
          child = Texture(textureId: controller.textureId!);
        } else {
          child = const SizedBox.shrink();
        }
        return AspectRatio(
          aspectRatio: ratio,
          child: child,
        );
      },
    );
  }

  double _ratioFromValue(NiumaPlayerValue value) {
    if (value.initialized &&
        value.size.width > 0 &&
        value.size.height > 0) {
      return value.size.width / value.size.height;
    }
    return 16 / 9;
  }
}
