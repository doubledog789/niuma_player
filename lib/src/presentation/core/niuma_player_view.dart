import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'package:niuma_player/src/data/video_player_backend.dart';
import 'package:niuma_player/src/domain/player_backend.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_controller.dart';
import 'package:niuma_player/src/presentation/fullscreen/niuma_fullscreen_page.dart'
    show NiumaFullscreenScope, webFullscreenRouteCountListenable;

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
          // [NiumaFullscreenPage] route 那侧的 NiumaPlayerView 通过
          // [NiumaFullscreenScope] InheritedWidget marker 渲染
          // [HtmlElementView]，inline 那侧（不在 scope 里）返 ColoredBox 让
          // element 让出，wrapper 元素在两个 platform-view 容器间 atomic
          // 移动。
          //
          // 全屏状态读 [webFullscreenRouteCountListenable]——进程级计数跟
          // [NiumaFullscreenPage] 路由生命周期挂钩，与 backend 实例解耦。
          // line failover swap backend 时新 backend 默认 webFullscreenState
          // 是 false，但 counter 不变，inline 不会误判退出全屏抢回 wrapper。
          final inFullscreenRoute =
              NiumaFullscreenScope.maybeOf(context) != null;
          return ValueListenableBuilder<int>(
            valueListenable: webFullscreenRouteCountListenable,
            builder: (ctx, count, __) {
              final inFullscreen = count > 0;
              if (inFullscreen && !inFullscreenRoute) {
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
