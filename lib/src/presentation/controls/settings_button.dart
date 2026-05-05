import 'package:flutter/material.dart';

import '../../niuma_sdk_assets.dart';
import '../niuma_player_theme.dart';
import 'niuma_sdk_icon.dart';

/// 顶栏设置入口——比 [MoreAction] 的 ⋮ 更显式的齿轮 icon。
///
/// 点击调用 [onTap]；宿主通常用来 push 一个画质 / 倍速 / 字幕的二级面板。
/// 不传 [onTap] 时按钮渲染但点击 no-op。
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return IconButton(
      onPressed: onTap,
      tooltip: '设置',
      icon: NiumaSdkIcon(
        asset: NiumaSdkAssets.icSettings,
        color: theme.actionIconColor,
        size: theme.actionIconSize,
      ),
    );
  }
}
