import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'package:niuma_player/src/data/video_player_backend.dart';
import 'package:niuma_player/src/domain/player_backend.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_controller.dart';
import 'package:niuma_player/src/presentation/fullscreen/web_fullscreen_overlay.dart';

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
        // web 优先：backend 暴露 htmlViewType（WebVideoBackend）→ HtmlElementView
        final viewType = backend?.htmlViewType;
        if (kIsWeb && viewType != null) {
          // Web fullscreen 模式：单 <video> element 不能两位置 mount——
          // overlay 的 NiumaPlayerView 通过 InheritedWidget marker 走渲染
          // 路径，inline 的 NiumaPlayerView 返 SizedBox 让 element 让出。
          final fsState = backend?.webFullscreenState;
          final isFs = fsState?.value ?? false;
          final inOverlay = WebFullscreenOverlayMarker.isInside(context);
          if (isFs && !inOverlay) {
            // inline 位置在 fullscreen 时不渲染 video
            return AspectRatio(
              aspectRatio: ratio,
              child: const ColoredBox(color: Color(0xFF000000)),
            );
          }
          // 用 ValueListenableBuilder 让 fullscreen 状态翻转时 inline /
          // overlay 都正确切渲染
          if (fsState != null) {
            return ValueListenableBuilder<bool>(
              valueListenable: fsState,
              builder: (ctx, _, __) {
                final stillIsFs = fsState.value;
                if (stillIsFs && !inOverlay) {
                  return AspectRatio(
                    aspectRatio: ratio,
                    child: const ColoredBox(color: Color(0xFF000000)),
                  );
                }
                return AspectRatio(
                  aspectRatio: ratio,
                  child: HtmlElementView(viewType: viewType),
                );
              },
            );
          }
          child = HtmlElementView(viewType: viewType);
        } else if (backend is VideoPlayerBackend) {
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
