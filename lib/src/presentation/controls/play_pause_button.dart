import 'package:flutter/material.dart';

import '../../domain/player_state.dart';
import '../niuma_player_controller.dart';
import '../niuma_player_theme.dart';

/// 播放 / 暂停切换按钮。
///
/// 监听 [NiumaPlayerController] 的 [NiumaPlayerValue.phase]：
/// - `playing` → 显示 pause 图标，点击调 [NiumaPlayerController.pause]
/// - 其它（paused / ready / buffering 等）→ 显示 play 图标，点击调
///   [NiumaPlayerController.play]
///
/// 颜色 / 尺寸读 [NiumaPlayerTheme.of]。
class PlayPauseButton extends StatelessWidget {
  /// 创建一个 [PlayPauseButton]。
  const PlayPauseButton({super.key, required this.controller});

  /// 该按钮观察并控制的 player controller。
  final NiumaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return ValueListenableBuilder<NiumaPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final isPlaying = value.phase == PlayerPhase.playing;
        return IconButton(
          padding: EdgeInsets.zero,
          iconSize: theme.iconSize,
          color: theme.iconColor,
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: () {
            if (isPlaying) {
              controller.pause();
            } else {
              controller.play();
            }
          },
        );
      },
    );
  }
}
