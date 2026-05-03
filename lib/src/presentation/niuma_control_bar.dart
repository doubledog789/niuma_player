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
        // 三档自适应宽度：
        // - <280dp（PiP 迷你窗）：只渲染 ScrubBar，整个 Row 不构造，避免
        //   RenderFlex overflow。
        // - 280-560dp（手机竖屏）：compact 模式——只留 5 个核心按钮：
        //   PlayPause / TimeDisplay / Volume / Fullscreen / Cast。藏掉
        //   Danmaku / Subtitle（M9 disabled placeholder）+ SpeedSelector
        //   （二级控件，全屏/Cast 后再调）。QualitySelector 单线路时本身
        //   就不渲染。
        // - ≥560dp（手机横屏 / 平板）：完整 10 个按钮 + Spacer。
        final tooNarrow = constraints.maxWidth < 280;
        final compact = constraints.maxWidth < 560;
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
                    const Spacer(),
                    if (!compact) const DanmakuButton(),
                    if (!compact) const SubtitleButton(),
                    if (!compact) SpeedSelector(controller: controller),
                    QualitySelector(controller: controller),
                    VolumeButton(controller: controller),
                    FullscreenButton(controller: controller),
                    NiumaCastButton(controller: controller),
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
