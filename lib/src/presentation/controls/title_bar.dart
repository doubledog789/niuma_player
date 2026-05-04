import 'package:flutter/material.dart';

import '../niuma_player_theme.dart';

/// 顶栏视频标题 + 副标题区域。
///
/// 必须放在 Row / Flex 下（用了 [Flexible] 限宽避免 overflow）。
/// 字体/颜色由 [NiumaPlayerTheme.videoTitleStyle] / [videoSubtitleStyle] 控制。
class TitleBar extends StatelessWidget {
  const TitleBar({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.videoTitleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.videoSubtitleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
