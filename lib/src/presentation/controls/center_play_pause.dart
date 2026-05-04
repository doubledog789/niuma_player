import 'package:flutter/material.dart';

import '../../niuma_sdk_assets.dart';
import '../niuma_player_controller.dart';
import '../niuma_player_theme.dart';
import 'niuma_sdk_icon.dart';

/// mockup 屏幕中央的大圆 PlayPause 按钮。
///
/// 仅在「视频暂停」+「控件可见」同时满足时渲染（mockup 设计语义：
/// 给暂停态一个明显的 resume 提示，播放中无需）。
///
/// 监听 controller 变化以响应 isPlaying 变化。
class CenterPlayPause extends StatelessWidget {
  const CenterPlayPause({
    super.key,
    required this.controller,
    required this.visible,
  });

  final NiumaPlayerController controller;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (ctx, _) {
        final isPaused = !controller.value.isPlaying;
        if (!visible || !isPaused) return const SizedBox.shrink();
        final theme = NiumaPlayerTheme.of(context);
        return Center(
          child: Material(
            color: theme.centerPlayPauseBackground,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => controller.play(),
              child: SizedBox(
                width: theme.centerPlayPauseSize,
                height: theme.centerPlayPauseSize,
                child: NiumaSdkIcon(
                  asset: NiumaSdkAssets.icPlay,
                  color: theme.actionIconColor,
                  size: theme.centerPlayPauseSize / 2,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
