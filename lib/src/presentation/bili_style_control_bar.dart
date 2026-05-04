import 'package:flutter/material.dart';

import 'button_override.dart';
import 'controls/back_action.dart';
import 'controls/cast_action.dart';
import 'controls/center_play_pause.dart';
import 'controls/danmaku_input_pill.dart';
import 'controls/danmaku_toggle.dart';
import 'controls/fullscreen_button.dart';
import 'controls/icon_label_action.dart';
import 'controls/line_switch_pill.dart';
import 'controls/more_action.dart';
import 'controls/pip_action.dart';
import 'controls/play_pause_button.dart';
import 'controls/scrub_bar.dart';
import 'controls/speed_selector.dart';
import 'controls/subtitle_button.dart';
import 'controls/time_display.dart';
import 'controls/title_bar.dart';
import 'controls/volume_button.dart';
import 'niuma_control_bar_config.dart';
import 'niuma_control_button.dart';
import 'niuma_player_controller.dart';
import 'niuma_player_theme.dart';

/// mockup B 站风格全屏控件层。
///
/// 按 [NiumaControlBarConfig] 的 enum list 决定渲染哪些按钮 / 顺序。
/// inline 状态请用现有 NiumaControlBar；本 widget 只服务全屏。
class BiliStyleControlBar extends StatelessWidget {
  const BiliStyleControlBar({
    super.key,
    required this.controller,
    required this.config,
    this.title,
    this.subtitle,
    this.chapters,
    this.controlsVisible = true,
    this.buttonOverrides,
    this.actionsBuilder,
    this.bottomActionsBuilder,
    this.rightRailBuilder,
    this.onBack,
    this.onCast,
    this.onPip,
    this.onMore,
    this.onDanmakuInputTap,
  });

  final NiumaPlayerController controller;
  final NiumaControlBarConfig config;
  final String? title;
  final String? subtitle;
  final List<Duration>? chapters;
  final bool controlsVisible;
  final Map<NiumaControlButton, ButtonOverride>? buttonOverrides;
  final WidgetBuilder? actionsBuilder;
  final WidgetBuilder? bottomActionsBuilder;
  final WidgetBuilder? rightRailBuilder;
  final VoidCallback? onBack;
  final VoidCallback? onCast;
  final VoidCallback? onPip;
  final VoidCallback? onMore;
  final VoidCallback? onDanmakuInputTap;

  Widget? _resolve(BuildContext ctx, NiumaControlButton btn) {
    final ov = buttonOverrides?[btn];
    if (ov is BuilderOverride) return ov.builder(ctx);
    if (ov is FieldsOverride) {
      // FieldsOverride 应用在 icon+label 类按钮（cast/pip 等）；其他类型回退默认。
      return IconLabelAction(
        icon: ov.icon ?? const Icon(Icons.help_outline),
        label: ov.label ?? '',
        onTap: ov.onTap ?? () {},
      );
    }
    return _renderDefault(btn);
  }

  Widget? _renderDefault(NiumaControlButton btn) {
    switch (btn) {
      case NiumaControlButton.back:
        return BackAction(onBack: onBack ?? () {});
      case NiumaControlButton.title:
        return title == null
            ? null
            : TitleBar(title: title!, subtitle: subtitle);
      case NiumaControlButton.cast:
        return CastAction(controller: controller, onTap: onCast);
      case NiumaControlButton.pip:
        return PipAction(controller: controller, onTap: onPip);
      case NiumaControlButton.lineSwitch:
        return LineSwitchPill(controller: controller);
      case NiumaControlButton.more:
        return MoreAction(onTap: onMore ?? () {});
      case NiumaControlButton.playPause:
        return PlayPauseButton(controller: controller);
      case NiumaControlButton.speed:
        return SpeedSelector(controller: controller);
      case NiumaControlButton.danmakuToggle:
        return DanmakuToggle(visibility: controller.danmakuVisibility);
      case NiumaControlButton.danmakuInput:
        return DanmakuInputPill(onTap: onDanmakuInputTap);
      case NiumaControlButton.subtitle:
        return const SubtitleButton();
      case NiumaControlButton.volume:
        return VolumeButton(controller: controller);
      case NiumaControlButton.fullscreen:
        return FullscreenButton(controller: controller);
      case NiumaControlButton.timeDisplay:
        return TimeDisplay(controller: controller);
      case NiumaControlButton.scrubBar:
        return ScrubBar(controller: controller, chapters: chapters);
    }
  }

  Iterable<Widget> _buildList(
      BuildContext ctx, List<NiumaControlButton> list) sync* {
    for (final btn in list) {
      final w = _resolve(ctx, btn);
      if (w != null) yield w;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    final gradColors = theme.controlsBackgroundGradient;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 顶栏
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradColors.reversed.toList(),
              ),
            ),
            child: Row(
              children: [
                ..._buildList(context, config.topLeading),
                const Spacer(),
                ..._buildList(context, config.topActions),
                if (actionsBuilder != null) actionsBuilder!(context),
              ],
            ),
          ),
        ),
        // 中央大圆 PlayPause
        if (config.centerPlayPause)
          CenterPlayPause(controller: controller, visible: controlsVisible),
        // 右侧 rail
        if (rightRailBuilder != null)
          Positioned(
            right: 14,
            top: 0,
            bottom: 0,
            child: Center(child: rightRailBuilder!(context)),
          ),
        // 底栏
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: gradColors.reversed.toList(),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 进度条 row：TimeDisplay 显示 "mm:ss / mm:ss"（current / total）一段字符串
                if (config.showProgressBar)
                  Row(
                    children: [
                      TimeDisplay(controller: controller),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ScrubBar(
                          controller: controller,
                          chapters: chapters,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ..._buildList(context, config.bottomLeft),
                    if (bottomActionsBuilder != null)
                      bottomActionsBuilder!(context),
                    const Spacer(),
                    ..._buildList(context, config.bottomRight),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
