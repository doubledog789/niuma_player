import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../domain/niuma_short_video_theme.dart';
import 'niuma_player_controller.dart';
import 'niuma_short_video_fullscreen_button.dart';
import 'niuma_short_video_player.dart';

/// 通过 [NiumaShortVideoFullscreenPage.route] push 的横屏短视频全屏播放页。
///
/// 行为契约（与 M9 [NiumaFullscreenPage] 保持一致）：
/// - **构造期**：锁定屏幕方向到 landscape（左 + 右），把 system UI 切到
///   `immersiveSticky`（隐藏状态栏与导航栏）。
/// - **dispose 期**：恢复 [DeviceOrientation.portraitUp]（先触发 Android
///   Activity reconfigure），下一帧再传空 list 释放锁定 + [SystemUiMode.edgeToEdge]。
/// - **Web 平台**：[SystemChrome] 在 web 上 no-op，显式用 [kIsWeb] 跳过。
/// - **页面内容**：黑色 [Scaffold] + [SafeArea]（top/bottom = false）+
///   内嵌 [NiumaShortVideoPlayer]，与外部 page 共享同一 [NiumaPlayerController]
///   实例（不重新 initialize）。
/// - **V1 决议**：横屏坐标系与竖屏 overlayBuilder 不兼容，V1 不透传
///   overlayBuilder（留给后续 landscapeOverlayBuilder API）。
///   默认在 leftCenter slot 渲染 [NiumaShortVideoFullscreenButton]，
///   按钮位于 [NiumaShortVideoFullscreenScope] 内，自动显示 fullscreen_exit
///   并在点击时 pop。
class NiumaShortVideoFullscreenPage extends StatefulWidget {
  /// 私有构造——使用方应通过 [NiumaShortVideoFullscreenPage.route] 拿到
  /// [Route<void>] 后再 [Navigator.push]。
  const NiumaShortVideoFullscreenPage._({
    required this.controller,
    this.theme,
  });

  /// 与外部 page 共享的 [NiumaPlayerController]。
  final NiumaPlayerController controller;

  /// 可选主题；为空则走 [NiumaShortVideoTheme.defaults]。
  final NiumaShortVideoTheme? theme;

  /// page route 的 settings.name。
  static const String routeName = 'NiumaShortVideoFullscreenPage';

  /// 创建一个 push 进横屏全屏短视频页的 [Route<void>]。
  ///
  /// 转场是 200ms 的淡入淡出，与 M9 [NiumaFullscreenPage.route] 保持一致。
  static Route<void> route({
    required NiumaPlayerController controller,
    NiumaShortVideoTheme? theme,
  }) {
    return PageRouteBuilder<void>(
      settings: const RouteSettings(name: routeName),
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => NiumaShortVideoFullscreenPage._(
        controller: controller,
        theme: theme,
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  State<NiumaShortVideoFullscreenPage> createState() =>
      _NiumaShortVideoFullscreenPageState();
}

/// InheritedWidget marker——出现在 [NiumaShortVideoFullscreenPage] 子树中代表
/// "本 build context 处于横屏全屏 page 内"。[NiumaShortVideoFullscreenButton]
/// 用 [maybeOf] 判定按钮该 push（进入全屏）还是 pop（退出全屏）。
///
/// **不导出**：本类是 niuma_player 内部使用的 marker，不属于公开 API。
/// 单测如需模拟"在 / 不在全屏页内"两种分支，可通过
/// `package:niuma_player/src/presentation/niuma_short_video_fullscreen_page.dart`
/// 的内部路径 import。
class NiumaShortVideoFullscreenScope extends InheritedWidget {
  /// 构造一个 marker scope。
  const NiumaShortVideoFullscreenScope({super.key, required super.child});

  /// 找最近的 [NiumaShortVideoFullscreenScope]——存在即返回非空 marker。
  static NiumaShortVideoFullscreenScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
        NiumaShortVideoFullscreenScope>();
  }

  @override
  bool updateShouldNotify(NiumaShortVideoFullscreenScope oldWidget) => false;
}

class _NiumaShortVideoFullscreenPageState
    extends State<NiumaShortVideoFullscreenPage> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      // Android 退全屏方向恢复需要两步走：
      //
      // 1) 先显式设 [portraitUp]——给 Activity 一个"竖屏"信号触发
      //    onConfigurationChanged，Android 把当前 surface 从横屏切回
      //    竖屏。如果不做这一步，仅传空 list 解锁，Activity 仍停在
      //    横屏 config 直到用户物理旋转设备。
      // 2) 下一帧再传空 list 释放锁定，让用户后续能按传感器自由旋转。
      SystemChrome.setPreferredOrientations(
        const <DeviceOrientation>[DeviceOrientation.portraitUp],
      );
      SchedulerBinding.instance.addPostFrameCallback((_) {
        SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
      });
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: NiumaShortVideoFullscreenScope(
          child: NiumaShortVideoPlayer(
            controller: widget.controller,
            theme: widget.theme,
            // 横屏：不透传 overlayBuilder（V1 决议）
            // 默认显示 fullscreen_exit 按钮（FullscreenButton 自动适配 in/out）
            leftCenterBuilder: (ctx, c) =>
                NiumaShortVideoFullscreenButton(controller: c),
          ),
        ),
      ),
    );
  }
}
