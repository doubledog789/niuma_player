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
    // padding/constraints 紧凑，避免 Material 默认 48dp hit area 让
    // ⋮ 离顶栏右边缘有空隙——mockup 是贴边的。minWidth=24 配合
    // BiliStyleControlBar 顶栏 Container right padding=0，让 ⋮ 距屏幕右 ~2px。
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      icon: Icon(
        Icons.more_horiz,
        color: theme.actionIconColor,
        size: theme.actionIconSize,
      ),
      onPressed: onTap,
      tooltip: '更多',
    );
  }
}
