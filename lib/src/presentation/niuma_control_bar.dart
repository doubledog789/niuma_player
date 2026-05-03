import 'package:flutter/material.dart';

import 'cast/niuma_cast_button.dart';
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
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // <280dp（PiP 迷你窗）：只渲染 ScrubBar，整个 Row 不构造，避免 PiP
        //   小窗里都没意义的控件 + RenderFlex assertion。
        // ≥280dp：左 PlayPause + TimeDisplay 固定，右侧按钮组放进 Expanded
        //   的横向 SingleChildScrollView (reverse=true) 里——
        //   - 容得下：所有按钮正常一行排开（视觉跟原 Row 一样）
        //   - 容不下（窄屏 320-430dp 手机）：右端 Cast 永远可见，其他按钮
        //     用户可横向滑动看到。永远不 overflow，永远不丢按钮。
        final tooNarrow = constraints.maxWidth < 280;
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
              if (!tooNarrow) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    PlayPauseButton(controller: controller),
                    const SizedBox(width: 8),
                    TimeDisplay(controller: controller),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        // reverse=true：内容右对齐 + 初始滚动位置在最右——
                        // 窄屏首屏看到的是 Cast 按钮（M15 重点），用户可
                        // 横向滑动看其他按钮。宽屏自然全显。
                        reverse: true,
                        child: Row(
                          children: [
                            const DanmakuButton(),
                            const SubtitleButton(),
                            SpeedSelector(controller: controller),
                            QualitySelector(controller: controller),
                            VolumeButton(controller: controller),
                            FullscreenButton(controller: controller),
                            NiumaCastButton(controller: controller),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
