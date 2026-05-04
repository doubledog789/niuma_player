import 'package:flutter/material.dart';

import '../niuma_player_theme.dart';

/// mockup 顶栏「图标 + 中文 label」垂直布局通用 widget。
///
/// 复用于 CastAction / PipAction 等顶栏 icon+label 按钮。样式由
/// [NiumaPlayerTheme.actionIconColor] / [actionIconSize] / [actionLabelStyle]
/// 全局控制。
class IconLabelAction extends StatelessWidget {
  const IconLabelAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme.merge(
            data: IconThemeData(
              color: theme.actionIconColor,
              size: theme.actionIconSize,
            ),
            child: icon,
          ),
          const SizedBox(height: 1),
          Text(label, style: theme.actionLabelStyle),
        ],
      ),
    );
    if (!enabled) return Opacity(opacity: 0.4, child: body);
    return InkWell(onTap: onTap, child: body);
  }
}
