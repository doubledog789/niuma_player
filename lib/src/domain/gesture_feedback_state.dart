// 本文件刻意不 import 'package:flutter/widgets.dart' —— domain 层不持有
// widget tree 概念。`IconData` 虽然来自 widgets 包，但它本身是个纯数据类
// （codePoint + fontFamily），是 SDK 对外暴露的 HUD 字段类型，按需 show 即可。
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show IconData;

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
    this.icon,
    this.iconAsset,
    this.hudIcon,
  });

  /// 当前手势类型。
  final GestureKind kind;

  /// 进度条值 0..1（HUD 默认渲染条形进度）。
  final double progress;

  /// 中央文字显示（如 "+15s / 1:23 / 4:56" 或 "65%" 或 "2x 倍速"）。
  final String? label;

  /// Material 图标。通用 fallback，HUD 在 [hudIcon] / [iconAsset] 都为 null
  /// 时渲染。
  final IconData? icon;

  /// 任意资源路径字符串（如消费方 app 的 SVG asset key）。HUD 看到非空时优先
  /// 用 `SvgPicture.asset` 渲染。**headless 核不再填这个字段**——核手势改发
  /// 语义 [hudIcon]，由消费方映射到自家资源。
  final String? iconAsset;

  /// 语义 HUD 图标（headless 核手势路径产出的字段）。消费方 HUD widget 把它
  /// 映射到自家 icon 资源（[GestureHudIcon.pause] → 暂停图标 等）。
  final GestureHudIcon? hudIcon;

  /// 返回字段更新后的新实例。
  GestureFeedbackState copyWith({
    GestureKind? kind,
    double? progress,
    String? label,
    IconData? icon,
    String? iconAsset,
    GestureHudIcon? hudIcon,
  }) =>
      GestureFeedbackState(
        kind: kind ?? this.kind,
        progress: progress ?? this.progress,
        label: label ?? this.label,
        icon: icon ?? this.icon,
        iconAsset: iconAsset ?? this.iconAsset,
        hudIcon: hudIcon ?? this.hudIcon,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GestureFeedbackState &&
          kind == other.kind &&
          progress == other.progress &&
          label == other.label &&
          icon == other.icon &&
          iconAsset == other.iconAsset &&
          hudIcon == other.hudIcon;

  @override
  int get hashCode =>
      Object.hash(kind, progress, label, icon, iconAsset, hudIcon);
}
