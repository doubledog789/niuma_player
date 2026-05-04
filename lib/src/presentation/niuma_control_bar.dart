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
import 'control_button_resolver.dart';
import 'niuma_control_bar_config.dart';
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
///
/// M16：传入 [config] 可切换为配置驱动模式；不传（默认 null）走 M9 老逻辑，
/// 向后兼容。
class NiumaControlBar extends StatelessWidget {
  /// 创建一个 [NiumaControlBar]。
  const NiumaControlBar({
    super.key,
    required this.controller,
    this.config,
  });

  /// 该控件条观察 / 控制的 player controller。所有原子控件共享同一实例。
  final NiumaPlayerController controller;

  /// M16 配置：传入时按 enum list 渲染；不传时走 M9 9 按钮老逻辑（向后兼容）。
  final NiumaControlBarConfig? config;

  @override
  Widget build(BuildContext context) {
    if (config != null) {
      return _ConfigDrivenBar(controller: controller, config: config!);
    }
    return _LegacyM9Bar(controller: controller);
  }
}

/// M9 9 按钮 layout，原 NiumaControlBar 实现照搬，行为不变。
class _LegacyM9Bar extends StatelessWidget {
  const _LegacyM9Bar({required this.controller});

  final NiumaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // <420dp（PiP 迷你窗 / 极窄 inline）：只渲染 ScrubBar，9 按钮 +
        //   Spacer 塞不下时整 Row 不构造，避免 RenderFlex assertion。
        // ≥420dp：完整 9 按钮 Row（Cast / PiP 移到视频右上角 actions 区，
        //   不再挤这条 ControlBar）。
        final compact = constraints.maxWidth < 420;
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
              if (!compact) ...[
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
            ],
          ),
        );
      },
    );
  }
}

/// M16 配置驱动 layout：按 enum list 渲染。
class _ConfigDrivenBar extends StatelessWidget {
  const _ConfigDrivenBar({required this.controller, required this.config});

  final NiumaPlayerController controller;
  final NiumaControlBarConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    final resolver = NiumaControlButtonResolver(controller: controller);
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
          if (config.showProgressBar) ScrubBar(controller: controller),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final btn in config.bottomLeft)
                resolver.resolveDefault(btn) ?? const SizedBox.shrink(),
              const Spacer(),
              for (final btn in config.bottomRight)
                resolver.resolveDefault(btn) ?? const SizedBox.shrink(),
            ],
          ),
        ],
      ),
    );
  }
}
