import 'package:flutter/widgets.dart';

/// 内部类：app 转 inactive 时触发 PiP enter，回 resumed 时调 [onResume]
/// 兜底重置 stale PiP state。不对外导出，由 `NiumaPlayerController` 持有。
/// 接受三个闭包而非 controller 引用，方便纯 Dart 单测。
class PipLifecycleObserver with WidgetsBindingObserver {
  /// 构造一个 observer。
  PipLifecycleObserver({
    required this.shouldEnter,
    required this.enter,
    this.onResume,
  });

  /// 业务闸门：返 true 才会触发 enter()。
  final bool Function() shouldEnter;

  /// PiP 触发动作。
  final Future<bool> Function() enter;

  /// 可选：app 回前台时的兜底回调，重置未收到 native 退出事件的 stale state。
  final VoidCallback? onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume?.call();
      return;
    }
    if (state != AppLifecycleState.inactive) return;
    if (!shouldEnter()) return;
    enter();
  }
}
