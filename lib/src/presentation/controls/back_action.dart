import 'package:flutter/material.dart';

import '../../niuma_sdk_assets.dart';
import '../niuma_player_theme.dart';
import 'niuma_sdk_icon.dart';

/// 顶栏返回按钮——全屏态点击退出全屏 (pop fullscreen route)。
class BackAction extends StatelessWidget {
  const BackAction({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return IconButton(
      icon: NiumaSdkIcon(
        asset: NiumaSdkAssets.icBack,
        size: 18,
        color: theme.actionIconColor,
      ),
      onPressed: onBack,
      tooltip: '返回',
    );
  }
}
