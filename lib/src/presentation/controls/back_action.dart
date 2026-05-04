import 'package:flutter/material.dart';

import '../niuma_player_theme.dart';

/// 顶栏返回按钮——全屏态点击退出全屏 (pop fullscreen route)。
class BackAction extends StatelessWidget {
  const BackAction({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return IconButton(
      icon: Icon(Icons.arrow_back_ios_new,
          color: theme.actionIconColor, size: 18),
      onPressed: onBack,
      tooltip: '返回',
    );
  }
}
