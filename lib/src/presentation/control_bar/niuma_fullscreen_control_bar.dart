import 'package:flutter/material.dart';

import 'package:niuma_player/src/presentation/control_bar/button_override.dart';
import 'package:niuma_player/src/presentation/control_bar/control_button_resolver.dart';
import 'package:niuma_player/src/presentation/controls/center_play_pause.dart';
import 'package:niuma_player/src/presentation/controls/icon_label_action.dart';
import 'package:niuma_player/src/presentation/controls/scrub_bar.dart';
import 'package:niuma_player/src/presentation/controls/time_display.dart';
import 'package:niuma_player/src/presentation/control_bar/niuma_control_bar_config.dart';
import 'package:niuma_player/src/presentation/control_bar/niuma_control_button.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_controller.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_theme.dart';

/// mockup B 站风格全屏控件层。
///
/// 按 [NiumaControlBarConfig] 的 enum list 决定渲染哪些按钮 / 顺序。
/// inline 状态请用现有 NiumaControlBar；本 widget 只服务全屏。
class NiumaFullscreenControlBar extends StatelessWidget {
  const NiumaFullscreenControlBar({
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
    this.bottomTrailingBuilder,
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
  final WidgetBuilder? bottomTrailingBuilder;
  final WidgetBuilder? rightRailBuilder;
  final VoidCallback? onBack;
  final VoidCallback? onCast;
  final VoidCallback? onPip;
  /// 接 BuildContext——`MoreAction` 自身 context，上层用 `findRenderObject()`
  /// 锚定 popup 到 ⋮ 按钮真实坐标。
  final ValueChanged<BuildContext>? onMore;
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
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // PiP 小窗 / 折叠状态 width 太小塞不下 mockup 控件，整个隐藏。
        // 阈值 280：手机竖屏最小 360-400，PiP 迷你窗 ~180-240。
        if (constraints.maxWidth < 280) {
          return const SizedBox.shrink();
        }
        return _buildContent(ctx);
      },
    );
  }

  Widget _buildContent(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradColors.reversed.toList(),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      ..._buildList(context, config.topLeading, resolver),
                    ],
                  ),
                ),
                if (actionsBuilder != null) actionsBuilder!(context),
                ..._buildList(context, config.topActions, resolver),
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
                // mockup 风格：时间独占一行（左对齐），进度条独占一行——
                // 不挤在同一 Row。
                if (config.showProgressBar) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TimeDisplay(controller: controller),
                  ),
                  const SizedBox(height: 4),
                  ScrubBar(controller: controller, chapters: chapters),
                ],
                const SizedBox(height: 8),
                // 用 LayoutBuilder + ConstrainedBox(maxWidth: 50%) + Spacer
                // 实现"两侧贴边、超出可滚"：
                //   - children 不超时：每侧 ConstrainedBox 占 own size（≤50%），
                //     Spacer 占余下空间——视觉等效原 Row + Spacer。
                //   - children 超时：每侧最多 50%，内部 SingleChildScrollView
                //     横向滚（右侧 reverse=true 滚动起点贴右），不再撞
                //     RenderFlex overflow assertion。
                LayoutBuilder(
                  builder: (ctx, constraints) {
                    final halfMax = constraints.maxWidth / 2;
                    return Row(
                      children: [
                        ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: halfMax),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ..._buildList(
                                    context, config.bottomLeft, resolver),
                                if (bottomActionsBuilder != null)
                                  bottomActionsBuilder!(context),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: halfMax),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 业务 trailing 在右侧 enum 之前——demo
                                // 用来把"选集"放在 倍速/线路切换 之前。
                                if (bottomTrailingBuilder != null)
                                  bottomTrailingBuilder!(context),
                                ..._buildList(
                                    context, config.bottomRight, resolver),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
