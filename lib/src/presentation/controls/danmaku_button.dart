import 'package:flutter/material.dart';

import '../niuma_player_theme.dart';

/// 弹幕按钮——M9 阶段**禁用**视觉，M11 启用真实逻辑。
///
/// 渲染一个灰色降透明度的对话泡图标，hover 显示 Tooltip "M11 启用"。
/// 不响应点击。M11 实装时直接替换本类内部，外部 API（无参 const
/// 构造）保持不变。
class DanmakuButton extends StatelessWidget {
  /// 创建一个 [DanmakuButton]。
  const DanmakuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return Tooltip(
      message: 'M11 启用',
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.4,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.chat_bubble_outline,
              size: theme.iconSize,
              color: theme.iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
