import 'package:flutter/material.dart';

import '../niuma_player_theme.dart';

/// mockup 顶栏三点菜单按钮——只渲染 IconButton；
/// 弹出内容由上层通过 [onTap] callback 自行实现（NiumaPlayer.moreMenuBuilder）。
class MoreAction extends StatelessWidget {
  const MoreAction({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return IconButton(
      icon: Icon(Icons.more_horiz, color: theme.actionIconColor, size: theme.actionIconSize),
      onPressed: onTap,
      tooltip: '更多',
    );
  }
}
