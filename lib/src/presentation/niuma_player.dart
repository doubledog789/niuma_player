import 'package:flutter/material.dart';

import 'niuma_control_bar.dart';
import 'niuma_player_controller.dart';
import 'niuma_player_theme.dart';
import 'niuma_player_view.dart';

/// niuma_player 一体化默认播放组件——M9 Task 8 的最小占位实现。
///
/// 仅渲染：[NiumaPlayerView] 叠 [NiumaControlBar]（始终可见）。
/// 完整的 auto-hide 状态机 / 广告 overlay 接入由 Task 9 实装。
class NiumaPlayer extends StatelessWidget {
  /// 创建一个 [NiumaPlayer]。
  const NiumaPlayer({
    super.key,
    required this.controller,
    this.theme,
  });

  /// 实际驱动播放的 controller。所有内部子组件共享同一实例。
  final NiumaPlayerController controller;

  /// 可选 UI 主题。非空时本组件在内部 build 顶上自动包一层
  /// [NiumaPlayerThemeData]——上层无需手动嵌套。
  final NiumaPlayerTheme? theme;

  @override
  Widget build(BuildContext context) {
    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        NiumaPlayerView(controller),
        Align(
          alignment: Alignment.bottomCenter,
          child: NiumaControlBar(controller: controller),
        ),
      ],
    );
    if (theme != null) {
      content = NiumaPlayerThemeData(data: theme!, child: content);
    }
    return content;
  }
}
