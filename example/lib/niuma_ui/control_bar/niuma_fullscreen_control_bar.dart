import 'package:flutter/material.dart';

import 'button_override.dart';
import 'control_button_resolver.dart';
import '../controls/center_play_pause.dart';
import '../controls/icon_label_action.dart';
import '../controls/scrub_bar.dart';
import '../controls/time_display.dart';
import 'niuma_control_bar_config.dart';
import 'niuma_control_button.dart';
import 'package:niuma_player/niuma_player.dart';
import '../core/niuma_player_theme.dart';

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

  /// 经验估算：单按钮 40-130 + 间距 12——决定底栏走单行还是双行布局。
  /// 估算偏保守（略大于实际），刚好临界场景倾向走双行避免溢出。
  static double _estimateBottomRowWidth({
    required NiumaControlBarConfig config,
    required bool hasBottomActions,
    required bool hasBottomTrailing,
    required bool multipleLines,
  }) {
    double w = 0;
    int count = 0;
    double widthOf(NiumaControlButton btn) {
      switch (btn) {
        case NiumaControlButton.danmakuInput:
          return 130; // pill 自带文本"发个友善的弹幕见证当下"
        case NiumaControlButton.danmakuToggle:
          return 70; // icon + switch
        case NiumaControlButton.title:
          return 200; // 标题文本占用大
        case NiumaControlButton.speed:
        case NiumaControlButton.lineSwitch:
          return 50; // 文字按钮 "1.0x" / "线路一"
        case NiumaControlButton.subtitle:
        case NiumaControlButton.volume:
          return 50;
        default:
          return 40; // 其它简单 icon 按钮
      }
    }

    for (final btn in config.bottomLeft) {
      w += widthOf(btn);
      count++;
    }
    for (final btn in config.bottomRight) {
      // lineSwitch 单线路时 LineSwitchPill 渲染为 SizedBox.shrink，不占宽度
      if (btn == NiumaControlButton.lineSwitch && !multipleLines) continue;
      w += widthOf(btn);
      count++;
    }
    if (hasBottomActions) {
      w += 80; // 业务自定义 action 按钮（典型"下一集"等文本按钮）
      count++;
    }
    if (hasBottomTrailing) {
      w += 80; // 同上（典型"选集 P1"）
      count++;
    }
    if (count > 1) {
      w += (count - 1) * 12; // Wrap spacing 12
    }
    // Container 自身 padding 已经在 LayoutBuilder.constraints.maxWidth
    // 之外被减掉，这里不再加。
    return w;
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
                // 底栏布局——双模式：
                //
                // **宽模式**（≥ 600px：iPhone 横屏 / iPad）：
                //   单行 Row + 两个 Flexible(loose) + Align，左组顶左、
                //   右组顶右，中间留空。视觉上保持 bili 风的"两组贴边"。
                //
                // **窄模式**（< 600px：iPhone 竖屏全屏 / PWA 模式）：
                //   两行 Column，第一行 leftWrap 左对齐，第二行 rightWrap
                //   右对齐——继续保持"左/右"的视觉语义，不再让按钮全挤一块。
                //
                // Wrap 自身的 `alignment.start/.end` 配合 `crossAxisAlignment.stretch`
                // 让窄屏每行单独占满宽度后再做内对齐——这样 danmakuInput
                // pill 整块完整渲染，不被裁也不被 ellipsis。
                LayoutBuilder(
                  builder: (ctx, constraints) {
                    final leftItems = <Widget>[
                      ..._buildList(context, config.bottomLeft, resolver),
                    ];
                    // bottomActionsBuilder（业务自定义 action，例如"下一集"）
                    // 放右组首位——之前放左组尾会让 narrow 模式下左组多
                    // 一项溢出到额外一行，layout 变成"左组 5 件占一行 +
                    // 自定义 action 占一行 + 右组占一行" 共 3 行。改放右组
                    // 后，narrow 模式下 [下一集] 跟 [选集/倍速/线路] 一起
                    // 在第二行右对齐，总共 2 行。语义上"自定义底栏 action"
                    // 也更接近右侧"settings/navigation"分组。
                    //
                    // bottomTrailingBuilder 仍在 enum 之前——保留 demo
                    // "选集"放在倍速/线路前的 ordering 约定。
                    final rightItems = <Widget>[
                      if (bottomActionsBuilder != null)
                        bottomActionsBuilder!(context),
                      if (bottomTrailingBuilder != null)
                        bottomTrailingBuilder!(context),
                      ..._buildList(context, config.bottomRight, resolver),
                    ];
                    final leftWrap = Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.start,
                      children: leftItems,
                    );
                    final rightWrap = Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.end,
                      children: rightItems,
                    );
                    // 估算总自然宽度，决定走单行 (Row + Spacer) 还是双行
                    // (Column)——不用固定阈值，因为同一窗宽下不同 config
                    // 答案不一样：短视频 (3 + 1 个 item) 在 iPhone 竖屏
                    // 366 应该单行；长视频 (8 个 item + pill) 在同样
                    // 366 必须双行。
                    //
                    // 估算策略：每枚 item 按经验值算（icon 40 / 文字按钮
                    // 50 / pill 130 / toggle 70 / builder 80），间距 12，
                    // lineSwitch 单线路时返 SizedBox.shrink 排除。估算 ≤
                    // 容器内宽则单行，否则双行。
                    final estimate = _estimateBottomRowWidth(
                      config: config,
                      hasBottomActions: bottomActionsBuilder != null,
                      hasBottomTrailing: bottomTrailingBuilder != null,
                      multipleLines: controller.source.lines.length > 1,
                    );
                    if (estimate <= constraints.maxWidth) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          leftWrap,
                          const Spacer(),
                          rightWrap,
                        ],
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        leftWrap,
                        const SizedBox(height: 6),
                        rightWrap,
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
