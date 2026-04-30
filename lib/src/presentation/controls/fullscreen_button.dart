import 'package:flutter/material.dart';

import '../niuma_fullscreen_page.dart';
import '../niuma_player_controller.dart';
import '../niuma_player_theme.dart';

/// 全屏切换按钮。
///
/// 点击时按所处 route 决定行为：
/// - 不在全屏 page 内（route name 不是 [NiumaFullscreenPage.routeName]）
///   → push 一个 [NiumaFullscreenPage.route]（淡入 200ms）；
/// - 已经在全屏 page 内 → [Navigator.pop] 回到上一层。
///
/// 图标也根据当前 route 切换：顶层显示 `fullscreen`，子 route 显示
/// `fullscreen_exit`。这样进入 / 退出全屏在同一按钮上视觉自洽。
class FullscreenButton extends StatelessWidget {
  /// 创建一个 [FullscreenButton]。
  const FullscreenButton({super.key, required this.controller});

  /// 全屏 page 中要复用的 player controller。push 路由时穿给
  /// [NiumaFullscreenPage]，进入 / 退出全屏不会重新 initialize。
  final NiumaPlayerController controller;

  /// 判断当前 build context 是否处于 [NiumaFullscreenPage] 内。
  ///
  /// 优先看 route 的 `settings.name`——`NiumaFullscreenPage.route` 始终
  /// 设置 [NiumaFullscreenPage.routeName]。若上层 host app 自己包装
  /// [NiumaFullscreenPage] 而没穿透 settings，回退用 `isFirst` 判断
  /// （顶层 route 一定不在全屏 page 内）。
  bool _inFullscreenPage(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route?.settings.name == NiumaFullscreenPage.routeName) return true;
    return !(route?.isFirst ?? true);
  }

  void _onPressed(BuildContext context) {
    if (_inFullscreenPage(context)) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).push(
        NiumaFullscreenPage.route(controller: controller),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    final inFullscreen = _inFullscreenPage(context);
    return IconButton(
      padding: EdgeInsets.zero,
      iconSize: theme.iconSize,
      color: theme.iconColor,
      icon: Icon(
        inFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
      ),
      onPressed: () => _onPressed(context),
    );
  }
}
