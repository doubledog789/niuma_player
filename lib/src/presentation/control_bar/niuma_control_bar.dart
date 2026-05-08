import 'package:flutter/material.dart';

import 'package:niuma_player/src/presentation/controls/danmaku_button.dart';
import 'package:niuma_player/src/presentation/controls/fullscreen_button.dart';
import 'package:niuma_player/src/presentation/controls/play_pause_button.dart';
import 'package:niuma_player/src/presentation/controls/quality_selector.dart';
import 'package:niuma_player/src/presentation/controls/scrub_bar.dart';
import 'package:niuma_player/src/presentation/controls/speed_selector.dart';
import 'package:niuma_player/src/presentation/controls/subtitle_button.dart';
import 'package:niuma_player/src/presentation/controls/time_display.dart';
import 'package:niuma_player/src/presentation/controls/volume_button.dart';
import 'package:niuma_player/src/presentation/control_bar/control_button_resolver.dart';
import 'package:niuma_player/src/presentation/control_bar/niuma_control_bar_config.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_controller.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_theme.dart';

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

/// inline 控件条 layout——按宽度三档响应式裁按钮：
///
/// | 宽度 | 行为 |
/// |---|---|
/// | < 280dp | 极窄（PiP 迷你窗 / cropped inline）：仅渲染 ScrubBar |
/// | 280–460dp | 中等（手机 16:9 inline 典型 ~393）：4 按钮 row——play / time / spacer / fullscreen |
/// | ≥ 460dp | 宽（iPad inline / desktop）：完整 9 按钮 row |
///
/// 之前所有 ≥ 420dp 都强渲完整 9 按钮，typical iPhone 16:9 inline 容器
/// (393pt 宽屏幕扣 padding) 落到这区间会撞 RenderFlex overflow——
/// 视频右下角出现黄黑斜纹警告条纹。新阈值让常见 inline 容器走中等档
/// 显示核心控件，避免溢出；业务侧想要完整按钮列表传
/// `NiumaControlBarConfig.bili` / `full` 通过 [_ConfigDrivenBar] 路径。
class _LegacyM9Bar extends StatelessWidget {
  const _LegacyM9Bar({required this.controller});

  final NiumaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        // 极窄：只 ScrubBar，整个 Row 不构造避免 overflow。
        if (w < 280) {
          return Container(
            padding: theme.controlBarPadding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: theme.controlsBackgroundGradient,
              ),
            ),
            child: ScrubBar(controller: controller),
          );
        }
        // ≥ 460dp 才能容下完整 9 按钮（按经验估每按钮 ~40-50px + spacing
        // + padding ≈ 480px 自然宽度）。
        final wide = w >= 460;
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
                  if (wide) ...[
                    const DanmakuButton(),
                    const SubtitleButton(),
                    SpeedSelector(controller: controller),
                    QualitySelector(controller: controller),
                    VolumeButton(controller: controller),
                  ],
                  FullscreenButton(controller: controller),
                ],
              ),
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
