import 'package:flutter/material.dart';

import 'button_override.dart';
import 'control_button_resolver.dart';
import 'controls/center_play_pause.dart';
import 'controls/icon_label_action.dart';
import 'controls/scrub_bar.dart';
import 'controls/time_display.dart';
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

  Widget? _resolve(
    BuildContext ctx,
    NiumaControlButton btn,
    NiumaControlButtonResolver resolver,
  ) {
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
    return resolver.resolveDefault(btn);
  }

  Iterable<Widget> _buildList(
    BuildContext ctx,
    List<NiumaControlButton> list,
    NiumaControlButtonResolver resolver,
  ) sync* {
    for (final btn in list) {
      final w = _resolve(ctx, btn, resolver);
      if (w != null) yield w;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    final gradColors = theme.controlsBackgroundGradient;
    final resolver = NiumaControlButtonResolver(
      controller: controller,
      title: title,
      subtitle: subtitle,
      chapters: chapters,
      onBack: onBack,
      onCast: onCast,
      onPip: onPip,
      onMore: onMore,
      onDanmakuInputTap: onDanmakuInputTap,
    );
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
                ..._buildList(context, config.topLeading, resolver),
                const Spacer(),
                ..._buildList(context, config.topActions, resolver),
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
                    ..._buildList(context, config.bottomLeft, resolver),
                    if (bottomActionsBuilder != null)
                      bottomActionsBuilder!(context),
                    const Spacer(),
                    ..._buildList(context, config.bottomRight, resolver),
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
