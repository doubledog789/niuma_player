import 'package:flutter/material.dart';

import 'package:niuma_player/src/presentation/controls/back_action.dart';
import 'package:niuma_player/src/presentation/controls/cast_action.dart';
import 'package:niuma_player/src/presentation/controls/danmaku_input_pill.dart';
import 'package:niuma_player/src/presentation/controls/danmaku_toggle.dart';
import 'package:niuma_player/src/presentation/controls/fullscreen_button.dart';
import 'package:niuma_player/src/presentation/controls/line_switch_pill.dart';
import 'package:niuma_player/src/presentation/controls/more_action.dart';
import 'package:niuma_player/src/presentation/controls/pip_action.dart';
import 'package:niuma_player/src/presentation/controls/play_pause_button.dart';
import 'package:niuma_player/src/presentation/controls/scrub_bar.dart';
import 'package:niuma_player/src/presentation/controls/speed_selector.dart';
import 'package:niuma_player/src/presentation/controls/subtitle_button.dart';
import 'package:niuma_player/src/presentation/controls/time_display.dart';
import 'package:niuma_player/src/presentation/controls/title_bar.dart';
import 'package:niuma_player/src/presentation/controls/volume_button.dart';
import 'package:niuma_player/src/presentation/control_bar/niuma_control_button.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_controller.dart';

/// 上下文：NiumaControlBar (inline) 和 NiumaFullscreenControlBar (fullscreen)
/// 共享的「按 enum 渲染默认 widget」逻辑。
///
/// 两个位置共用，避免 enum case 在多处分别维护。
class NiumaControlButtonResolver {
  const NiumaControlButtonResolver({
    required this.controller,
    this.title,
    this.subtitle,
    this.chapters,
    this.onBack,
    this.onCast,
    this.onPip,
    this.onMore,
    this.onDanmakuInputTap,
  });

  final NiumaPlayerController controller;
  final String? title;
  final String? subtitle;
  final List<Duration>? chapters;
  final VoidCallback? onBack;
  final VoidCallback? onCast;
  final VoidCallback? onPip;
  /// 接 BuildContext——`MoreAction` 的自身 context，给上层 `findRenderObject()`
  /// 锚定 popup 用。
  final ValueChanged<BuildContext>? onMore;
  final VoidCallback? onDanmakuInputTap;

  /// 返回 enum 对应的默认 widget。返回 null 表示该 enum 在当前上下文不渲染（如
  /// inline 状态的 back/title/cast 等顶栏专用 enum）。
  Widget? resolveDefault(NiumaControlButton btn) {
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
        return MoreAction(onTap: onMore ?? (_) {});
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
}
