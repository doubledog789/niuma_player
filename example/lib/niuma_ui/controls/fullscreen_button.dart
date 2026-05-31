import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';
import '../core/niuma_player_theme.dart';
import '../fullscreen/niuma_fullscreen_page.dart';
import 'niuma_sdk_icon.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    // push / pop + 配置透传逻辑已抽到 NiumaPlayerController 的
    // [NiumaFullscreenControl] 扩展（toggleFullscreen / isInFullscreen），
    // 业务可在任意自定义按钮上复用同一入口。
    final inFullscreen = controller.isInFullscreen(context);
    return IconButton(
      padding: EdgeInsets.zero,
      iconSize: theme.iconSize,
      color: theme.iconColor,
      icon: NiumaSdkIcon(
        asset: NiumaSdkAssets.fullscreenIcon(isFullscreen: inFullscreen),
        size: theme.iconSize,
        color: theme.iconColor,
      ),
      onPressed: () => controller.toggleFullscreen(context),
    );
  }
}
