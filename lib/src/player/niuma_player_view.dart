import 'package:flutter/foundation.dart' show Factory, kIsWeb;
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart'
    show AndroidViewController, PlatformViewsService, StandardMessageCodec;
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'package:niuma_player/src/data/video_player_backend.dart';
import 'package:niuma_player/src/domain/player_backend.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/player/niuma_player_controller.dart';
import 'package:niuma_player/src/player/web_fullscreen_coordination.dart'
    show NiumaFullscreenScope, webFullscreenRouteCountListenable;

/// 渲染 [NiumaPlayerController] 当前激活的 backend。
/// backend 切换（例如回退到 IJK）时自动 rebuild。
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

  /// Android Native Texture 路径下视频纹理的缩放过滤等级；iOS / Web 由
  /// 原生 / 浏览器自行缩放，本参数无关。
  /// 默认 [FilterQuality.medium]——比 Texture 默认的 low 画质高一档，开销无感。
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NiumaPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final backend = controller.backend;
        final ratio = aspectRatio ?? _ratioFromValue(value);
        final Widget child;
        // web 优先：backend 暴露 htmlViewType → HtmlElementView
        final viewType = backend?.htmlViewType;
        if (kIsWeb && viewType != null) {
          // 单 <video> 不能两处 mount：全屏路由那份（在 NiumaFullscreenScope
          // 里）挂 HtmlElementView，inline 那份返 ColoredBox 让出元素。
          // 全屏状态读进程级路由计数，与 backend 实例解耦（failover 换
          // backend 不会让 inline 误判抢回 <video>）。
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
          // iOS：VideoPlayer 内部走 AVPlayer 原生 scaling。
          child = VideoPlayer(backend.innerController);
        } else if (backend != null &&
            backend.androidPlatformViewId != null) {
          // Android PlatformView 路径（useAndroidPlatformView=true）。
          // 必须用 initExpensiveAndroidView 的纯 Hybrid Composition：其它方式
          // 会走/回退 Virtual Display，抓不到 SurfaceView 独立 Surface 的像素
          // → 有声黑屏（flutter#128920 / #107313）。
          child = PlatformViewLink(
            viewType: 'cn.niuma/player_surface',
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers:
                  const <Factory<OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
            ),
            onCreatePlatformView: (params) {
              final controller = PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: 'cn.niuma/player_surface',
                layoutDirection: TextDirection.ltr,
                creationParams: <String, dynamic>{
                  'instanceId': backend.androidPlatformViewId,
                },
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => params.onFocusChanged(true),
              );
              controller.addOnPlatformViewCreatedListener(
                params.onPlatformViewCreated,
              );
              controller.create();
              return controller;
            },
          );
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
