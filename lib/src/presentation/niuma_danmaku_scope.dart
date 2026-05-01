import 'package:flutter/widgets.dart';

import 'niuma_danmaku_controller.dart';

/// InheritedWidget marker，让子树（如 [DanmakuButton]）通过 context 找到
/// 上层注入的 [NiumaDanmakuController]。
///
/// `NiumaPlayer` 内部在接到 `danmakuController` 时会自动注入此 scope。
/// 用户也可以手动包一层用于自定义布局。
class NiumaDanmakuScope extends InheritedWidget {
  /// 构造一个 scope。
  const NiumaDanmakuScope({
    super.key,
    required this.controller,
    required super.child,
  });

  /// 被注入的 controller。
  final NiumaDanmakuController controller;

  /// 找最近的 scope。无则返回 null。
  static NiumaDanmakuController? maybeOf(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<NiumaDanmakuScope>();
    return s?.controller;
  }

  @override
  bool updateShouldNotify(NiumaDanmakuScope oldWidget) =>
      oldWidget.controller != controller;
}
