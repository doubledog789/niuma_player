import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/presentation/controls/niuma_sdk_icon.dart';
import 'package:niuma_player/src/presentation/fullscreen/niuma_fullscreen_page.dart';
import 'package:niuma_player/src/presentation/fullscreen/web_fullscreen_overlay.dart';

/// 全屏切换按钮。
///
/// 点击时按所处 route 决定行为：
/// - 不在全屏 page 内（route name 不是 [NiumaFullscreenPage.routeName]）
///   → push 一个 [NiumaFullscreenPage.route]（淡入 200ms）；
/// - 已经在全屏 page 内 → [Navigator.pop] 回到上一层。
///
/// 图标也根据当前 route 切换：顶层显示 `fullscreen`，子 route 显示
/// `fullscreen_exit`。这样进入 / 退出全屏在同一按钮上视觉自洽。
class FullscreenButton extends StatelessWidget {
  /// 创建一个 [FullscreenButton]。
  const FullscreenButton({super.key, required this.controller});

  /// 全屏 page 中要复用的 player controller。push 路由时穿给
  /// [NiumaFullscreenPage]，进入 / 退出全屏不会重新 initialize。
  final NiumaPlayerController controller;

  /// 判断当前 build context 是否处于 [NiumaFullscreenPage] 内。
  ///
  /// 通过 [NiumaFullscreenScope] InheritedWidget marker 检测——只有
  /// 真正在全屏页里的子树才能拿到这个 marker。早先版本用
  /// `route.isFirst` 当兜底，会把任何非 home 路由（比如 example
  /// 里 push 上去的 demo 页）误判为"在全屏内"，导致按钮把 demo 页
  /// 自身 pop 掉而不是进入全屏，所以彻底去掉那条 fallback。
  bool _inFullscreenPage(BuildContext context) {
    return NiumaFullscreenScope.maybeOf(context) != null;
  }

  void _onPressed(BuildContext context) {
    // Web 路径：Flutter Overlay 假全屏——OverlayEntry 推全屏 NiumaPlayer
    // 复用同 controller，inline 那侧 NiumaPlayerView 检测 fullscreen 状态
    // 返 SizedBox 让 <video> element 给 overlay 用——单 element 在 widget
    // tree 中只 mount 一处，不抢。Flutter 控件保留并叠加在 video 上。
    if (kIsWeb) {
      if (isWebFlutterFullscreenActive()) {
        exitWebFlutterFullscreen(controller: controller);
      } else {
        final cfg = NiumaPlayerConfigScope.maybeOf(context);
        final inheritedTheme = cfg?.theme ?? NiumaPlayerTheme.of(context);
        enterWebFlutterFullscreen(
          context: context,
          controller: controller,
          fullscreenChildBuilder: (ctx) => SafeArea(
            child: NiumaPlayer(
              controller: controller,
              theme: inheritedTheme,
              adSchedule: cfg?.adSchedule,
              adAnalyticsEmitter: cfg?.adAnalyticsEmitter,
              pauseVideoDuringAd: cfg?.pauseVideoDuringAd ?? true,
              controlsAutoHideAfter:
                  cfg?.controlsAutoHideAfter ?? const Duration(seconds: 5),
              danmakuController: cfg?.danmakuController,
              disabledGestures: cfg?.disabledGestures ?? const {},
              gestureHudBuilder: cfg?.gestureHudBuilder,
              title: cfg?.title,
              subtitle: cfg?.subtitle,
              controlBarConfig: cfg?.controlBarConfig,
              fullscreenControlBarConfig:
                  cfg?.fullscreenControlBarConfig ??
                      NiumaControlBarConfig.bili,
              buttonOverrides: cfg?.buttonOverrides,
              bottomActionsBuilder: cfg?.bottomActionsBuilder,
              bottomTrailingBuilder: cfg?.bottomTrailingBuilder,
              pausedOverlayBuilder: cfg?.pausedOverlayBuilder,
              rightRailBuilder: cfg?.rightRailBuilder,
              moreMenuBuilder: cfg?.moreMenuBuilder,
              chapters: cfg?.chapters,
              onDanmakuInputTap: cfg?.onDanmakuInputTap,
            ),
          ),
        );
      }
      return;
    }
    if (_inFullscreenPage(context)) {
      Navigator.of(context).pop();
    } else {
      // 从外层 NiumaPlayer 注入的 NiumaPlayerConfigScope 把 adSchedule /
      // emitter / pauseVideoDuringAd / autoHide / theme 一并透传到全屏
      // 页，避免全屏页里的内层 NiumaPlayer 丢失外层配置。
      //
      // theme 字段优先用 NiumaPlayer.theme（cfg.theme），为 null 时退到
      // 通过 [NiumaPlayerThemeData] InheritedWidget 注入的当前主题
      // ([NiumaPlayerTheme.of])——README 推荐的用法是
      // `NiumaPlayerThemeData(child: NiumaPlayer(controller: ctl))`
      // 此时 NiumaPlayer.theme=null，没这个 fallback 全屏页就拿不到外层
      // inherited 主题，造成视觉回归。
      final cfg = NiumaPlayerConfigScope.maybeOf(context);
      final inheritedTheme =
          cfg?.theme ?? NiumaPlayerTheme.of(context);
      Navigator.of(context).push(
        NiumaFullscreenPage.route(
          controller: controller,
          theme: inheritedTheme,
          adSchedule: cfg?.adSchedule,
          adAnalyticsEmitter: cfg?.adAnalyticsEmitter,
          pauseVideoDuringAd: cfg?.pauseVideoDuringAd ?? true,
          controlsAutoHideAfter:
              cfg?.controlsAutoHideAfter ?? const Duration(seconds: 5),
          danmakuController: cfg?.danmakuController,
          disabledGestures: cfg?.disabledGestures ?? const {},
          gestureHudBuilder: cfg?.gestureHudBuilder,
          // M16 参数：从 NiumaPlayerConfigScope 读取后透传给全屏页，
          // 确保全屏 NiumaFullscreenControlBar 能正确渲染 mockup 配置。
          title: cfg?.title,
          subtitle: cfg?.subtitle,
          controlBarConfig: cfg?.controlBarConfig,
          fullscreenControlBarConfig:
              cfg?.fullscreenControlBarConfig ?? NiumaControlBarConfig.bili,
          buttonOverrides: cfg?.buttonOverrides,
          bottomActionsBuilder: cfg?.bottomActionsBuilder,
          bottomTrailingBuilder: cfg?.bottomTrailingBuilder,
          pausedOverlayBuilder: cfg?.pausedOverlayBuilder,
          rightRailBuilder: cfg?.rightRailBuilder,
          moreMenuBuilder: cfg?.moreMenuBuilder,
          chapters: cfg?.chapters,
          onDanmakuInputTap: cfg?.onDanmakuInputTap,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    // web 上"在全屏"语义 = 在 fullscreen overlay 内（marker 存在）
    final inFullscreen = kIsWeb
        ? WebFullscreenOverlayMarker.isInside(context)
        : _inFullscreenPage(context);
    return IconButton(
      padding: EdgeInsets.zero,
      iconSize: theme.iconSize,
      color: theme.iconColor,
      icon: NiumaSdkIcon(
        asset: NiumaSdkAssets.fullscreenIcon(isFullscreen: inFullscreen),
        size: theme.iconSize,
        color: theme.iconColor,
      ),
      onPressed: () => _onPressed(context),
    );
  }
}
