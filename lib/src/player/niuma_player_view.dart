import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'package:niuma_player/src/data/video_player_backend.dart';
import 'package:niuma_player/src/domain/player_backend.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/player/niuma_player_controller.dart';
import 'package:niuma_player/src/player/web_fullscreen_coordination.dart'
    show NiumaFullscreenScope, webFullscreenRouteCountListenable;

/// 渲染 [NiumaPlayerController] 当前激活的 backend。
///
/// backend 切换（例如回退到 IJK）时自动 rebuild，调用方直接把它丢
/// 进 widget tree 即可。
class NiumaPlayerView extends StatelessWidget {
  const NiumaPlayerView(
    this.controller, {
    super.key,
    this.aspectRatio,
    this.filterQuality = FilterQuality.medium,
  });

  final NiumaPlayerController controller;

  /// 为 null 时回落到 `controller.value.size`。两者都不可用时渲染
  /// 16:9 占位框以保持布局稳定。
  final double? aspectRatio;

  /// **Android Native** Texture 路径下视频纹理的缩放过滤等级。
  ///
  /// 默认 [FilterQuality.medium]——比 Flutter `Texture` 的硬编码默认
  /// [FilterQuality.low]（双线性）画质明显提升一档，尤其在大屏 / 高 DPI
  /// 手机上拉伸视频不再糊；medium 用双三次插值，开销在 2020+ 中端机以上
  /// 完全无感。
  ///
  /// 仅 Android Native（ExoPlayer / IJK 通过 Flutter Texture 渲染）路径
  /// 生效。iOS 由 `VideoPlayer` widget 内部走 AVPlayer 原生 scaling，本
  /// 参数无关；web `<video>` 由浏览器直接缩放，本参数同样无关。
  ///
  /// 极致性能场景（feed 多实例 + 低端机）可显式传 [FilterQuality.low]
  /// 降回旧默认；追求极致画质可传 [FilterQuality.high]，但每帧 GPU 开销
  /// 显著增加，不建议常规使用。
  final FilterQuality filterQuality;

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
          // iOS 路径：VideoPlayer widget 内部走 AVPlayer 原生 scaling，无需上层
          // 控制 filterQuality（且本版 video_player 也未暴露该参数）。
          child = VideoPlayer(backend.innerController);
        } else if (backend != null &&
            backend.kind == PlayerBackendKind.native &&
            controller.textureId != null) {
          child = Texture(
            textureId: controller.textureId!,
            filterQuality: filterQuality,
          );
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
    if (value.initialized && value.size.width > 0 && value.size.height > 0) {
      return value.size.width / value.size.height;
    }
    return 16 / 9;
  }
}
