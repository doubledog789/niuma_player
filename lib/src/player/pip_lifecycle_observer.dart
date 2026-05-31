import 'package:flutter/widgets.dart';

/// **内部类**：监听 app lifecycle 兼顾两件事：
///
/// 1. [AppLifecycleState.inactive]：触发 PiP enter（autoEnter 模式）；
/// 2. [AppLifecycleState.resumed]：调用 [onResume] 兜底——典型用途是
///    Android 模拟器 / 部分设备退出 PiP 时不可靠地触发
///    `onPictureInPictureModeChanged(false)`，导致 controller 残留
///    `value.isInPictureInPicture=true`，控件层一直被藏。app 回前台
///    时 onResume 强制重置该 stale state。
///
/// 不通过 `lib/niuma_player.dart` 导出。`NiumaPlayerController` 注册并持有。
///
/// **设计：** 接受三个闭包而不是直接持 controller 引用——
/// - `shouldEnter`: 业务闸门（playing + !inPip + autoEnter 等）
/// - `enter`: 触发动作（一般是 controller.enterPictureInPicture）
/// - `onResume`: 可选的"回前台兜底"回调
///
/// 解耦让单测极简：直接 mock 三个闭包就能验全分支。
class PipLifecycleObserver with WidgetsBindingObserver {
  /// 构造一个 observer。
  PipLifecycleObserver({
    required this.shouldEnter,
    required this.enter,
    this.onResume,
  });

  /// 业务闸门：返 true 才会触发 enter()。
  final bool Function() shouldEnter;

  /// PiP 触发动作。返回 [Future]&lt;bool&gt;（虽然 observer 不读，签名对齐 controller）。
  final Future<bool> Function() enter;

  /// 可选：app 回到 [AppLifecycleState.resumed]（前台）时调用的兜底回调。
  /// 用于重置 PiP 期间没收到 native 退出事件导致的 stale state。
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
