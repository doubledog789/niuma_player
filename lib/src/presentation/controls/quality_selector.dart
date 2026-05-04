import 'package:flutter/material.dart';

import '../../niuma_sdk_assets.dart';
import '../niuma_player_controller.dart';
import '../niuma_player_theme.dart';
import 'niuma_sdk_icon.dart';

/// 画质 / 线路选择按钮——读 [NiumaPlayerController.source]'s `lines`，
/// 展开 popup 列出全部线路；选中时调 [NiumaPlayerController.switchLine]。
///
/// 当 `source.lines.length == 1`（单线路场景）时不渲染——返回
/// [SizedBox.shrink]，避免在没有可切换内容时占位。
class QualitySelector extends StatelessWidget {
  /// 创建一个 [QualitySelector]。
  const QualitySelector({super.key, required this.controller});

  /// 该按钮控制其线路切换的 player controller。
  final NiumaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final lines = controller.source.lines;
    if (lines.length <= 1) return const SizedBox.shrink();

    final theme = NiumaPlayerTheme.of(context);
    return PopupMenuButton<String>(
      iconSize: theme.iconSize,
      iconColor: theme.iconColor,
      tooltip: '画质',
      icon: NiumaSdkIcon(
        asset: NiumaSdkAssets.icQuality,
        size: theme.iconSize,
        color: theme.iconColor,
      ),
      itemBuilder: (context) => [
        for (final line in lines)
          PopupMenuItem<String>(
            value: line.id,
            child: Text(line.label),
          ),
      ],
      onSelected: controller.switchLine,
    );
  }
}
