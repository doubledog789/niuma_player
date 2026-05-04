import 'package:flutter/foundation.dart';

import 'niuma_control_button.dart';

/// 声明式控件区域配置：每个 enum list 决定渲染顺序和显隐。
///
/// list 顺序 = 渲染顺序；不在 list 里的按钮就不显示。
@immutable
class NiumaControlBarConfig {
  const NiumaControlBarConfig({
    this.topLeading = const [],
    this.topActions = const [],
    this.bottomLeft = const [],
    this.bottomRight = const [],
    this.centerPlayPause = false,
    this.showProgressBar = true,
  });

  /// 顶栏左侧（一般是 [back, title]）。
  final List<NiumaControlButton> topLeading;

  /// 顶栏右侧（[cast, pip, lineSwitch, more] 等）；后面追加 actionsBuilder slot。
  final List<NiumaControlButton> topActions;

  /// 底栏左侧（playPause/speed 等）；后面追加 bottomActionsBuilder slot。
  final List<NiumaControlButton> bottomLeft;

  /// 底栏右侧（弹幕 toggle/input 等）。
  final List<NiumaControlButton> bottomRight;

  /// 是否启用中央大圆 PlayPause（暂停态 + 控件可见时显示）。
  final bool centerPlayPause;

  /// 是否显示进度条 row（time + scrubBar + time）。
  final bool showProgressBar;

  /// 最简（基础 UI / inline 默认）。
  /// progressBar row 自带左右 time，所以 bottomLeft 不放 timeDisplay。
  static const minimal = NiumaControlBarConfig(
    topLeading: [NiumaControlButton.back, NiumaControlButton.title],
    bottomLeft: [NiumaControlButton.playPause],
    bottomRight: [NiumaControlButton.fullscreen],
    showProgressBar: true,
  );

  /// mockup B 站风格（全屏默认）。
  /// v2（M16 follow-up）：cast/pip 收进 more 菜单，lineSwitch 移到底栏右侧。
  static const bili = NiumaControlBarConfig(
    topLeading: [NiumaControlButton.back, NiumaControlButton.title],
    topActions: [NiumaControlButton.more],
    bottomLeft: [
      NiumaControlButton.playPause,
      NiumaControlButton.danmakuToggle,
      NiumaControlButton.danmakuInput,
    ],
    bottomRight: [
      NiumaControlButton.speed,
      NiumaControlButton.lineSwitch,
    ],
    centerPlayPause: true,
    showProgressBar: true,
  );

  /// debug 全开（所有按钮）。
  static const full = NiumaControlBarConfig(
    topLeading: [NiumaControlButton.back, NiumaControlButton.title],
    topActions: [
      NiumaControlButton.cast,
      NiumaControlButton.pip,
      NiumaControlButton.lineSwitch,
      NiumaControlButton.more,
    ],
    bottomLeft: [
      NiumaControlButton.playPause,
      NiumaControlButton.speed,
    ],
    bottomRight: [
      NiumaControlButton.subtitle,
      NiumaControlButton.volume,
      NiumaControlButton.danmakuToggle,
      NiumaControlButton.danmakuInput,
    ],
    centerPlayPause: true,
    showProgressBar: true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NiumaControlBarConfig &&
          listEquals(other.topLeading, topLeading) &&
          listEquals(other.topActions, topActions) &&
          listEquals(other.bottomLeft, bottomLeft) &&
          listEquals(other.bottomRight, bottomRight) &&
          other.centerPlayPause == centerPlayPause &&
          other.showProgressBar == showProgressBar;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(topLeading),
        Object.hashAll(topActions),
        Object.hashAll(bottomLeft),
        Object.hashAll(bottomRight),
        centerPlayPause,
        showProgressBar,
      );
}
