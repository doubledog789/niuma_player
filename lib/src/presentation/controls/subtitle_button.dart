import 'package:flutter/material.dart';

import 'package:niuma_player/src/niuma_sdk_assets.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_theme.dart';
import 'package:niuma_player/src/presentation/controls/niuma_sdk_icon.dart';

/// 字幕按钮——M9 阶段**禁用**视觉，M10 启用真实逻辑。
///
/// 渲染一个灰色降透明度的字幕图标，hover 显示 Tooltip "M10 启用"。
/// 不响应点击，避免上层逻辑误以为字幕已启用。M10 实装时直接替换
/// 本类内部即可，外部 API（无参 const 构造）保持不变。
class SubtitleButton extends StatelessWidget {
  /// 创建一个 [SubtitleButton]。
  const SubtitleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return Tooltip(
      message: 'M10 启用',
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.4,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: NiumaSdkIcon(
              asset: NiumaSdkAssets.icSubtitle,
              size: theme.iconSize,
              color: theme.iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
