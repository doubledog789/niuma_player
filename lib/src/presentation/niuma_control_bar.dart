import 'package:flutter/material.dart';

import 'controls/danmaku_button.dart';
import 'controls/fullscreen_button.dart';
import 'controls/play_pause_button.dart';
import 'controls/quality_selector.dart';
import 'controls/scrub_bar.dart';
import 'controls/speed_selector.dart';
import 'controls/subtitle_button.dart';
import 'controls/time_display.dart';
import 'controls/volume_button.dart';
import 'niuma_player_controller.dart';
import 'niuma_player_theme.dart';

/// B 站风格的密集底部控件条。
///
/// 把 9 个原子控件 + 进度条按"上 ScrubBar / 下 Row of buttons"两层组合：
/// - 顶层：[ScrubBar]——铺满宽度
/// - 底层（左→右）：
///   1. [PlayPauseButton]
///   2. [TimeDisplay]
///   3. [Spacer]
///   4. [DanmakuButton]（M9 disabled）
///   5. [SubtitleButton]（M9 disabled）
///   6. [SpeedSelector]
///   7. [QualitySelector]——`source.lines.length <= 1` 时自动隐藏
///   8. [VolumeButton]
///   9. [FullscreenButton]
///
/// 容器背景使用 [NiumaPlayerTheme.controlsBackgroundGradient] 渲染一段
/// 上→下的 [LinearGradient]（默认 transparent → black87），让控件叠在
/// 视频上仍有可读性。padding 走 [NiumaPlayerTheme.controlBarPadding]。
///
/// 调用方覆盖外观的方式：在 [NiumaControlBar] 之上挂一层
/// [NiumaPlayerThemeData]，调整 13 个主题字段中需要变的那几个。
class NiumaControlBar extends StatelessWidget {
  /// 创建一个 [NiumaControlBar]。
  const NiumaControlBar({super.key, required this.controller});

  /// 该控件条观察 / 控制的 player controller。所有原子控件共享同一实例。
  final NiumaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: theme.controlsBackgroundGradient,
        ),
      ),
      padding: theme.controlBarPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScrubBar(controller: controller),
          const SizedBox(height: 4),
          Row(
            children: [
              PlayPauseButton(controller: controller),
              const SizedBox(width: 8),
              TimeDisplay(controller: controller),
              const Spacer(),
              const DanmakuButton(),
              const SubtitleButton(),
              SpeedSelector(controller: controller),
              QualitySelector(controller: controller),
              VolumeButton(controller: controller),
              FullscreenButton(controller: controller),
            ],
          ),
        ],
      ),
    );
  }
}
