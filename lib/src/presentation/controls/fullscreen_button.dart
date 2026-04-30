import 'package:flutter/material.dart';

import '../niuma_player_controller.dart';
import '../niuma_player_theme.dart';

/// 全屏切换按钮。
///
/// 点击时按所处 route 决定行为：
/// - 顶层（`ModalRoute.of(context)?.isFirst == true`）→ push 一个新的
///   全屏 page；
/// - 子 route（即"已经在全屏 page"）→ pop 回上一层。
///
/// **TODO(m9-task8)**：这里 push 的目标暂时是 placeholder MaterialPageRoute
/// （Scaffold + 文字 "FullscreenPage placeholder"），等 Task 8 实装
/// `NiumaFullscreenPage` 后改成它。这样做能让 Task 4 单独可 commit /
/// 通过测试，而不需要先把 NiumaFullscreenPage 写完。
class FullscreenButton extends StatelessWidget {
  /// 创建一个 [FullscreenButton]。
  const FullscreenButton({super.key, required this.controller});

  /// 在全屏 page 中要复用的 player controller。Task 8 实装时把它穿到
  /// NiumaFullscreenPage。
  final NiumaPlayerController controller;

  void _onPressed(BuildContext context) {
    final isFirstRoute = ModalRoute.of(context)?.isFirst ?? true;
    if (isFirstRoute) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            // TODO(m9-task8): 替换为 NiumaFullscreenPage(controller: controller)
            body: Center(child: Text('FullscreenPage placeholder')),
          ),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    final isFirstRoute = ModalRoute.of(context)?.isFirst ?? true;
    return IconButton(
      padding: EdgeInsets.zero,
      iconSize: theme.iconSize,
      color: theme.iconColor,
      icon: Icon(
        isFirstRoute ? Icons.fullscreen : Icons.fullscreen_exit,
      ),
      onPressed: () => _onPressed(context),
    );
  }
}
