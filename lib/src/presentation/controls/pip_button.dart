import 'package:flutter/material.dart';

import '../../niuma_sdk_assets.dart';
import '../niuma_player_controller.dart';
import '../niuma_player_theme.dart';
import 'niuma_sdk_icon.dart';

/// PiP（画中画）开关按钮。
///
/// 三档可达性：
/// 1. `controller.value.isPictureInPictureSupported == false`
///    → [IgnorePointer] 灰禁（设备不支持 / 未 initialize）
/// 2. `controller.value.isInPictureInPicture == true`
///    → 高亮图标 [Icons.picture_in_picture_alt]，tap 调 exitPictureInPicture
/// 3. 否则普通图标 [Icons.picture_in_picture_alt_outlined]，
///    tap 调 enterPictureInPicture
///
/// 默认由 [NiumaPlayer] 自动叠在视频右上角浮层（Task 8）；用户也可
/// 手动放进自定义布局。
class PipButton extends StatelessWidget {
  /// 构造一个按钮。
  const PipButton({super.key, required this.controller});

  /// 被驱动的 controller。
  final NiumaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (ctx, _) {
        final v = controller.value;
        if (!v.isPictureInPictureSupported) {
          return const IgnorePointer(
            ignoring: true,
            child: IconButton(
              onPressed: null,
              icon: NiumaSdkIcon(
                asset: NiumaSdkAssets.icPip,
                color: Colors.white38,
              ),
              tooltip: 'PiP（设备不支持）',
            ),
          );
        }
        if (v.isInPictureInPicture) {
          return IconButton(
            onPressed: () => controller.exitPictureInPicture(),
            icon: NiumaSdkIcon(
              asset: NiumaSdkAssets.icPipExit,
              color: theme.iconColor,
            ),
            tooltip: '退出画中画',
          );
        }
        return IconButton(
          onPressed: () => controller.enterPictureInPicture(),
          icon: NiumaSdkIcon(
            asset: NiumaSdkAssets.icPip,
            color: theme.iconColor,
          ),
          tooltip: '进入画中画',
        );
      },
    );
  }
}
