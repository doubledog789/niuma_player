import 'package:flutter/widgets.dart';

/// 按钮覆盖策略：完全替换 widget，或仅替换 icon/label/onTap 字段。
sealed class ButtonOverride {
  const ButtonOverride();

  const factory ButtonOverride.builder(WidgetBuilder builder) = BuilderOverride;

  const factory ButtonOverride.fields({
    Widget? icon,
    String? label,
    VoidCallback? onTap,
  }) = FieldsOverride;
}

/// 完全替换：SDK 渲染 [builder] 的结果，结构由用户控制。
class BuilderOverride extends ButtonOverride {
  const BuilderOverride(this.builder);
  final WidgetBuilder builder;
}

/// 字段替换：保留 SDK 内置结构，只替换 icon/label/onTap 三选其一。
class FieldsOverride extends ButtonOverride {
  const FieldsOverride({this.icon, this.label, this.onTap});
  final Widget? icon;
  final String? label;
  final VoidCallback? onTap;
}
