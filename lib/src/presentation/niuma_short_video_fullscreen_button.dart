import 'package:flutter/material.dart';

import '../niuma_sdk_assets.dart';
import 'controls/niuma_sdk_icon.dart';
import 'glass_card.dart';
import 'niuma_danmaku_controller.dart';
import 'niuma_fullscreen_page.dart';
import 'niuma_player_controller.dart';
import 'niuma_player_theme.dart';

/// 抖音风短视频"切全屏"按钮。
///
/// 在 [NiumaFullscreenScope] 子树之外（即"内嵌"语义下）
/// 显示 [Icons.fullscreen]，点击 push M9 [NiumaFullscreenPage]（长视频风：
/// 含完整 ControlBar + M13 全手势 + scrub bar + 速度/画质选择器）。
///
/// 在 [NiumaFullscreenScope] 子树之内（即"已经在全屏页内"），
/// 显示 [Icons.fullscreen_exit]，点击 [Navigator.pop] 退出。
class NiumaShortVideoFullscreenButton extends StatelessWidget {
  /// 构造一个全屏按钮。
  const NiumaShortVideoFullscreenButton({
    super.key,
    required this.controller,
    this.size = 36,
    this.danmakuController,
    this.theme,
  });

  /// 共享 controller——push route 时透传，保证视频不重新 init。
  final NiumaPlayerController controller;

  /// 按钮整体尺寸（圆形）。
  final double size;

  /// 可选弹幕 controller——push 全屏 route 时透传，全屏后弹幕继续可用。
  final NiumaDanmakuController? danmakuController;

  /// 可选主题——push 全屏 route 时透传，全屏后主题继续可用。
  final NiumaPlayerTheme? theme;

  @override
  Widget build(BuildContext context) {
    final inFullscreen = NiumaFullscreenScope.maybeOf(context) != null;
    return GestureDetector(
      onTap: () {
        if (inFullscreen) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).push(
            NiumaFullscreenPage.route(
              controller: controller,
              danmakuController: danmakuController,
              theme: theme,
            ),
          );
        }
      },
      child: GlassCard(
        radius: 999,
        padding: EdgeInsets.all(size * 0.18),
        child: NiumaSdkIcon(
          asset: NiumaSdkAssets.fullscreenIcon(isFullscreen: inFullscreen),
          color: Colors.white,
          size: size * 0.55,
        ),
      ),
    );
  }
}
