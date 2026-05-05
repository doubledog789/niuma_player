import 'package:flutter/material.dart';

import '../niuma_player_theme.dart';

/// mockup 顶栏三点菜单按钮——只渲染 IconButton；
/// 弹出内容由上层通过 [onTap] callback 自行实现（NiumaPlayer.moreMenuBuilder）。
///
/// [onTap] 的 [BuildContext] 参数是按钮自己 build 出来的 context——上层
/// 拿它做 `findRenderObject()` 即可锚定 popup 到按钮真实屏幕坐标，无需
/// MediaQuery 硬算。
class MoreAction extends StatelessWidget {
  const MoreAction({super.key, required this.onTap});

  final ValueChanged<BuildContext> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    // 不用 IconButton——它默认 MaterialTapTargetSize.padded 强制 48×48
    // 最小 hit area 且 IconButton 不暴露这个参数让我们关掉。
    // InkWell + Padding + Icon 自己控制 size，保证 ⋮ icon 紧贴 button 右
    // 边、配合 BiliStyleControlBar Container right padding=0，icon 距屏幕
    // 右仅 ~6px (Padding 右 6px)。
    return Tooltip(
      message: '更多',
      child: InkWell(
        onTap: () => onTap(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Icon(
            Icons.more_horiz,
            color: theme.actionIconColor,
            size: theme.actionIconSize,
          ),
        ),
      ),
    );
  }
}
