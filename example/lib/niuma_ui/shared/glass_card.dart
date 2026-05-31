import 'dart:ui';

import 'package:flutter/material.dart';

/// 项目通用毛玻璃卡片：BackdropFilter blur 18 + 半透明黑底 + 白细边。
///
/// niuma_player 多处需要这种"暗色 HUD"风格（手势 HUD、短视频 scrub
/// label 等），统一在此实现。背景色由调用方传 [color]，默认
/// `Colors.black.withValues(alpha: 0.55)`。
class GlassCard extends StatelessWidget {
  /// 构造一个毛玻璃卡片。
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
    this.radius = 14,
    this.color,
    this.blurSigma = 18,
  });

  /// 内容。
  final Widget child;

  /// 内边距。
  final EdgeInsets padding;

  /// 圆角半径。
  final double radius;

  /// 背景色——null 时用 `Colors.black.withValues(alpha: 0.55)`。
  final Color? color;

  /// 毛玻璃模糊强度。
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
