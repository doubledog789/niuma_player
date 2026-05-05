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
                // Material 圆环外壳 (theme.centerPlayPauseBackground) 已经
                // 是按钮底；中间走 icPlay 三角让 ColorFilter 干净地染 brand
                // 橙——不用 icPlayCircle 避免 SVG 内置圆环 srcIn 后变成不
                // 透明色块跟外层 Material 圆叠出怪异轮廓。
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
