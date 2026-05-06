import 'package:flutter/material.dart';

import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_controller.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_theme.dart';

/// 进度时间显示——`mm:ss / mm:ss` 格式（`position / duration`）。
///
/// 字体使用 [NiumaPlayerTheme.timeTextStyle]，默认带 tabular-figures
/// 字距，避免数字跳动时整体宽度抖动。
class TimeDisplay extends StatelessWidget {
  /// 创建一个 [TimeDisplay]。
  const TimeDisplay({super.key, required this.controller});

  /// 提供 position / duration 的 player controller。
  final NiumaPlayerController controller;

  /// 把 [Duration] 格式化为 `mm:ss`。负值与超出 60 分钟时仍按 `mm:ss`
  /// 截到分秒——M9 范围内不处理超长媒体；M11+ 再考虑 `hh:mm:ss`。
  static String formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return ValueListenableBuilder<NiumaPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final pos = formatDuration(value.position);
        final dur = formatDuration(value.duration);
        return Text(
          '$pos / $dur',
          style: theme.timeTextStyle,
        );
      },
    );
  }
}
