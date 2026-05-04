// lib/src/presentation/niuma_short_video_pause_indicator.dart
import 'package:flutter/material.dart';

import '../domain/niuma_short_video_theme.dart';
import '../niuma_sdk_assets.dart';
import 'controls/niuma_sdk_icon.dart';

/// 短视频暂停态中央粘性图标。
///
/// 在 `phase=paused` 时由父组件挂上，`play()` 后立刻消失（无淡出，
/// 避免点击响应延迟感）。本组件不响应自身 hit-test，tap 透传给底下单击层。
///
/// 入场带 80ms ease-out scale 动画（0.8 → 1.0），用 [TweenAnimationBuilder]
/// 隐式实现，无 [State] 类、无控制器。
class NiumaShortVideoPauseIndicator extends StatelessWidget {
  /// 构造一个暂停指示器。
  const NiumaShortVideoPauseIndicator({super.key, required this.theme});

  /// 主题。
  final NiumaShortVideoTheme theme;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.8, end: 1.0),
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          width: theme.pauseIndicatorSize,
          height: theme.pauseIndicatorSize,
          decoration: BoxDecoration(
            color: theme.pauseIndicatorBackgroundColor,
            shape: BoxShape.circle,
          ),
          child: NiumaSdkIcon(
            asset: NiumaSdkAssets.icPlayCircle,
            color: theme.pauseIndicatorIconColor,
            size: theme.pauseIndicatorIconSize,
          ),
        ),
      ),
    );
  }
}
