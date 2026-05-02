import 'package:flutter/material.dart';

import 'glass_card.dart';
import 'niuma_player_controller.dart';
import 'niuma_short_video_fullscreen_page.dart';

/// 抖音风短视频"切横屏全屏"按钮。
///
/// 在 [NiumaShortVideoFullscreenPage] 子树之外（即"竖屏内嵌"语义下）
/// 显示 [Icons.fullscreen]，点击 push 横屏全屏 route。
///
/// 在 [NiumaShortVideoFullscreenPage] 子树之内（即"已经在全屏页内"），
/// 显示 [Icons.fullscreen_exit]，点击 [Navigator.pop] 退出。
class NiumaShortVideoFullscreenButton extends StatelessWidget {
  /// 构造一个全屏按钮。
  const NiumaShortVideoFullscreenButton({
    super.key,
    required this.controller,
    this.size = 36,
  });

  /// 共享 controller——push route 时透传，保证视频不重新 init。
  final NiumaPlayerController controller;

  /// 按钮整体尺寸（圆形）。
  final double size;

  @override
  Widget build(BuildContext context) {
    final inFullscreen =
        NiumaShortVideoFullscreenScope.maybeOf(context) != null;
    return GestureDetector(
      onTap: () {
        if (inFullscreen) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).push(
            NiumaShortVideoFullscreenPage.route(controller: controller),
          );
        }
      },
      child: GlassCard(
        radius: 999,
        padding: EdgeInsets.all(size * 0.18),
        child: Icon(
          inFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
          color: Colors.white,
          size: size * 0.55,
        ),
      ),
    );
  }
}
