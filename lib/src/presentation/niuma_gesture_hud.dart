import 'package:flutter/material.dart';

import '../domain/gesture_feedback_state.dart';

/// 默认 HUD widget（B 站风）：暗色圆角矩形 + 图标 + 文字 + 进度条。
///
/// 主题色由 `Theme.of(context).colorScheme.primary` 控制（进度条着色）。
/// 业务想完全替换视觉，传 `gestureHudBuilder` 给 [NiumaGestureLayer]。
class NiumaGestureHud extends StatelessWidget {
  /// 构造一个 HUD。
  const NiumaGestureHud({super.key, required this.state});

  /// 当前 HUD 状态。
  final GestureFeedbackState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.icon != null)
            Icon(state.icon, color: Colors.white, size: 32),
          if (state.label != null) ...[
            const SizedBox(height: 6),
            Text(
              state.label!,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              value: state.progress.clamp(0.0, 1.0),
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
