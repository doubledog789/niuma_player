import 'package:flutter/material.dart';

/// `NiumaPlayer` 在 `phase=ended` 时渲染的默认结束视图。
///
/// 中央圆按钮 + "重播" 文字。业务方传 [NiumaPlayer.endedBuilder] 即可
/// 完全替换本默认 UI；只想换图标 / 配色的自己 wrap 一层调整 props。
///
/// **注意**：当 `controller.setLooping(true)` 时 native 端不会触发
/// `phase=ended`——视频无缝重播——此 widget 不会显示。这个组件主要
/// 服务非循环播放场景（点播 / 单条短视频等）。
class NiumaEndedView extends StatelessWidget {
  /// 创建一个默认结束视图。
  ///
  /// [onReplay] 非 null 时按钮可点击，业务侧实现通常调
  /// `controller.seekTo(Duration.zero)` + `controller.play()`。null 时
  /// 按钮变灰禁用。
  const NiumaEndedView({
    super.key,
    this.onReplay,
    this.iconColor,
    this.iconBackgroundColor,
    this.label = '重播',
    this.size = 64,
  });

  final VoidCallback? onReplay;

  /// 重播图标颜色。null 走主题 onSurface。
  final Color? iconColor;

  /// 背景圆色。null 走 黑@0.5。
  final Color? iconBackgroundColor;

  /// 按钮下方文字。默认 "重播"；传空串隐藏。
  final String label;

  /// 圆按钮尺寸。
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconC = iconColor ?? theme.colorScheme.onSurface;
    final bg = iconBackgroundColor ?? Colors.black.withValues(alpha: 0.5);
    final disabled = onReplay == null;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: bg,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onReplay,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(
                  Icons.replay,
                  color: disabled ? iconC.withValues(alpha: 0.4) : iconC,
                  size: size * 0.55,
                ),
              ),
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: iconC,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
