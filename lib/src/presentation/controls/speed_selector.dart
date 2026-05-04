import 'package:flutter/material.dart';

import '../../niuma_sdk_assets.dart';
import '../niuma_player_controller.dart';
import '../niuma_player_theme.dart';
import 'niuma_sdk_icon.dart';

/// 倍速选择按钮——展开 popup 列出 0.5x / 1.0x / 1.5x / 2.0x。
///
/// 选中某档时调 [NiumaPlayerController.setPlaybackSpeed]。
class SpeedSelector extends StatelessWidget {
  /// 创建一个 [SpeedSelector]。
  const SpeedSelector({super.key, required this.controller});

  /// 该按钮控制其倍速的 player controller。
  final NiumaPlayerController controller;

  /// 可选的倍速档位。M9 写死这 4 档；M10+ 可考虑通过主题或参数自定义。
  static const List<double> speeds = [0.5, 1.0, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return PopupMenuButton<double>(
      iconSize: theme.iconSize,
      iconColor: theme.iconColor,
      tooltip: '倍速',
      icon: NiumaSdkIcon(
        asset: NiumaSdkAssets.icSpeed,
        size: theme.iconSize,
        color: theme.iconColor,
      ),
      itemBuilder: (context) => [
        for (final s in speeds)
          PopupMenuItem<double>(
            value: s,
            child: Text('${s}x'),
          ),
      ],
      onSelected: controller.setPlaybackSpeed,
    );
  }
}
