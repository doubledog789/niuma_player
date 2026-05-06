import 'package:flutter/widgets.dart';

/// **内部类**：监听 [AppLifecycleState.inactive] 触发 PiP enter。
///
/// 不通过 `lib/niuma_player.dart` 导出。`NiumaPlayerController` 在
/// `autoEnterPictureInPictureOnBackground=true` 时实例化并 addObserver，
/// false 时 removeObserver。
///
/// **设计：** 接受两个闭包而不是直接持 controller 引用——
/// - `shouldEnter`: 业务闸门（playing + !inPip + autoEnter 等）
/// - `enter`: 触发动作（一般是 controller.enterPictureInPicture）
///
/// 解耦让单测极简：直接 mock 两个闭包就能验全分支。
class PipLifecycleObserver with WidgetsBindingObserver {
  /// 构造一个 observer。
  PipLifecycleObserver({
    required this.shouldEnter,
    required this.enter,
  });

  /// 业务闸门：返 true 才会触发 enter()。
  final bool Function() shouldEnter;

  /// PiP 触发动作。返回 [Future]&lt;bool&gt;（虽然 observer 不读，签名对齐 controller）。
  final Future<bool> Function() enter;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.inactive) return;
    if (!shouldEnter()) return;
    enter();
  }
}
