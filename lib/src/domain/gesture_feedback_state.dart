import 'package:flutter/foundation.dart' show immutable;

import 'package:niuma_player/src/domain/gesture_hud_icon.dart';
import 'package:niuma_player/src/domain/gesture_kind.dart';

/// 手势 HUD 数据快照。
@immutable
class GestureFeedbackState {
  /// 构造一个 HUD 状态。
  const GestureFeedbackState({
    required this.kind,
    required this.progress,
    this.label,
    this.hudIcon,
  });

  /// 当前手势类型。
  final GestureKind kind;

  /// 进度条值 0..1（HUD 默认渲染条形进度）。
  final double progress;

  /// 中央文字显示（如 "+15s / 1:23 / 4:56" 或 "65%" 或 "2x 倍速"）。
  final String? label;

  /// 语义 HUD 图标（headless 核手势路径产出的字段）。消费方 HUD widget 把它
  /// 映射到自家 icon 资源（[GestureHudIcon.pause] → 暂停图标 等）。
  final GestureHudIcon? hudIcon;

  /// 返回字段更新后的新实例。
  GestureFeedbackState copyWith({
    GestureKind? kind,
    double? progress,
    String? label,
    GestureHudIcon? hudIcon,
  }) =>
      GestureFeedbackState(
        kind: kind ?? this.kind,
        progress: progress ?? this.progress,
        label: label ?? this.label,
        hudIcon: hudIcon ?? this.hudIcon,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GestureFeedbackState &&
          kind == other.kind &&
          progress == other.progress &&
          label == other.label &&
          hudIcon == other.hudIcon;

  @override
  int get hashCode => Object.hash(kind, progress, label, hudIcon);
}
