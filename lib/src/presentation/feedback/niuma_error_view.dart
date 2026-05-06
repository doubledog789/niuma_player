import 'package:flutter/material.dart';

import 'package:niuma_player/src/domain/player_state.dart';

/// `NiumaPlayer` 在 `phase=error` 时渲染的默认错误视图。
///
/// 居中显示错误图标 + 错误信息 + 可选 "重试" 按钮。业务方传
/// [NiumaPlayer.errorBuilder] 参数即可完全替换本默认 UI；只想换文案 /
/// 配色的，自己 wrap 一层 [NiumaErrorView] 调整 props 即可。
class NiumaErrorView extends StatelessWidget {
  /// 创建一个默认错误视图。
  ///
  /// [error] 来自 `controller.value.error`，可能为 null（仅当业务**直接**
  /// 用此 widget 而非通过 NiumaPlayer 触发）。null 时显示通用错误文案。
  /// [onRetry] 非 null 时显示重试按钮，点击触发回调；业务侧通常实现为
  /// `controller.initialize()` 或切换 line。
  const NiumaErrorView({
    super.key,
    this.error,
    this.onRetry,
    this.iconColor,
    this.textColor,
    this.title,
  });

  final PlayerError? error;
  final VoidCallback? onRetry;

  /// 错误图标颜色。null 走 [Theme.of(context).colorScheme.error]。
  final Color? iconColor;

  /// 文字颜色。null 走 onSurface。
  final Color? textColor;

  /// 标题文字。null 时根据 error.category 自动选合适文案：
  ///   - codecUnsupported → "视频格式不支持"
  ///   - network → "网络异常"
  ///   - terminal → "无法播放"
  ///   - 其它 → "播放出错"
  final String? title;

  String _defaultTitle() {
    if (title != null) return title!;
    final cat = error?.category;
    switch (cat) {
      case PlayerErrorCategory.codecUnsupported:
        return '视频格式不支持';
      case PlayerErrorCategory.network:
        return '网络异常';
      case PlayerErrorCategory.terminal:
        return '无法播放';
      case PlayerErrorCategory.transient:
      case PlayerErrorCategory.unknown:
      case null:
        return '播放出错';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconC = iconColor ?? theme.colorScheme.error;
    final textC = textColor ?? theme.colorScheme.onSurface;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: iconC, size: 48),
          const SizedBox(height: 12),
          Text(
            _defaultTitle(),
            style: TextStyle(
              color: textC,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (error?.message != null) ...[
            const SizedBox(height: 4),
            Text(
              error!.message,
              style: TextStyle(
                color: textC.withValues(alpha: 0.7),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              style: TextButton.styleFrom(
                foregroundColor: textC,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
