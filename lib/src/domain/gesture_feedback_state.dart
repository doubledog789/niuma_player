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
    this.iconAsset,
  });

  /// 当前手势类型。
  final GestureKind kind;

  /// 进度条值 0..1（HUD 默认渲染条形进度）。
  final double progress;

  /// 中央文字显示（如 "+15s / 1:23 / 4:56" 或 "65%" 或 "2x 倍速"）。
  final String? label;

  /// Material 图标。仅在 [iconAsset] 为 null 时由默认 HUD 渲染——
  /// niuma 资源包覆盖到的图标走 [iconAsset]，没覆盖到的（如亮度）走 [icon]。
  final IconData? icon;

  /// niuma SDK SVG 资源路径（[NiumaSdkAssets.icXxx]）。优先于 [icon]——
  /// 默认 HUD 看到非空时用 [SvgPicture.asset] 渲染，让品牌视觉贯穿手势 HUD。
  final String? iconAsset;

  /// 返回字段更新后的新实例。
  GestureFeedbackState copyWith({
    GestureKind? kind,
    double? progress,
    String? label,
    IconData? icon,
    String? iconAsset,
  }) =>
      GestureFeedbackState(
        kind: kind ?? this.kind,
        progress: progress ?? this.progress,
        label: label ?? this.label,
        icon: icon ?? this.icon,
        iconAsset: iconAsset ?? this.iconAsset,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GestureFeedbackState &&
          kind == other.kind &&
          progress == other.progress &&
          label == other.label &&
          icon == other.icon &&
          iconAsset == other.iconAsset;

  @override
  int get hashCode => Object.hash(kind, progress, label, icon, iconAsset);
}
