import 'package:flutter/widgets.dart';

import 'gesture_kind.dart';

/// 手势 HUD 数据快照。
@immutable
class GestureFeedbackState {
  /// 构造一个 HUD 状态。
  const GestureFeedbackState({
    required this.kind,
    required this.progress,
    this.label,
    this.icon,
  });

  /// 当前手势类型。
  final GestureKind kind;

  /// 进度条值 0..1（HUD 默认渲染条形进度）。
  final double progress;

  /// 中央文字显示（如 "+15s / 1:23 / 4:56" 或 "65%" 或 "2x 倍速"）。
  final String? label;

  /// 图标（默认 NiumaGestureHud 渲染时用）。
  final IconData? icon;

  /// 返回字段更新后的新实例。
  GestureFeedbackState copyWith({
    GestureKind? kind,
    double? progress,
    String? label,
    IconData? icon,
  }) =>
      GestureFeedbackState(
        kind: kind ?? this.kind,
        progress: progress ?? this.progress,
        label: label ?? this.label,
        icon: icon ?? this.icon,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GestureFeedbackState &&
          kind == other.kind &&
          progress == other.progress &&
          label == other.label &&
          icon == other.icon;

  @override
  int get hashCode => Object.hash(kind, progress, label, icon);
}
