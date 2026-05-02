import 'dart:ui';

import 'package:flutter/material.dart';

import '../domain/gesture_feedback_state.dart';
import '../domain/gesture_kind.dart';

/// 默认手势 HUD（B 站 / YouTube 风）。
///
/// 按 [GestureFeedbackState.kind] 选不同视觉：
/// - [GestureKind.horizontalSeek]：大字号时间 + 细进度条
/// - [GestureKind.brightness]：暖黄图标 + 百分比 + 进度条
/// - [GestureKind.volume]：白图标 + 百分比 + 进度条
/// - [GestureKind.longPressSpeed]：胶囊（"2x 倍速"）
/// - [GestureKind.doubleTap]：圆形图标闪现（无进度条）
///
/// 业务想完全替换视觉，传 `gestureHudBuilder` 给 NiumaGestureLayer。
class NiumaGestureHud extends StatelessWidget {
  /// 构造一个 HUD。
  const NiumaGestureHud({super.key, required this.state});

  /// 当前 HUD 状态。
  final GestureFeedbackState state;

  @override
  Widget build(BuildContext context) {
    switch (state.kind) {
      case GestureKind.horizontalSeek:
        return _SeekCard(state: state);
      case GestureKind.brightness:
      case GestureKind.volume:
        return _ValueCard(state: state);
      case GestureKind.longPressSpeed:
        return _SpeedPill(state: state);
      case GestureKind.doubleTap:
        return _IconFlash(state: state);
    }
  }
}

class _Glass extends StatelessWidget {
  const _Glass({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
    this.radius = 14,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
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

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color, this.width = 150});

  final double value;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          minHeight: 3,
          value: value.clamp(0.0, 1.0),
          backgroundColor: Colors.white.withValues(alpha: 0.18),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

class _SeekCard extends StatelessWidget {
  const _SeekCard({required this.state});
  final GestureFeedbackState state;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.label != null) ...[
            Text(
              state.label!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 12),
          ],
          _ProgressBar(value: state.progress, color: Colors.white, width: 200),
        ],
      ),
    );
  }
}

class _ValueCard extends StatelessWidget {
  const _ValueCard({required this.state});
  final GestureFeedbackState state;

  @override
  Widget build(BuildContext context) {
    final isBrightness = state.kind == GestureKind.brightness;
    final accent = isBrightness ? const Color(0xFFFCD34D) : Colors.white;
    return _Glass(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.icon != null) ...[
            Icon(state.icon, color: accent, size: 36),
            const SizedBox(height: 10),
          ],
          if (state.label != null) ...[
            Text(
              state.label!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 12),
          ],
          _ProgressBar(value: state.progress, color: accent),
        ],
      ),
    );
  }
}

class _SpeedPill extends StatelessWidget {
  const _SpeedPill({required this.state});
  final GestureFeedbackState state;

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      radius: 999,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.icon != null) ...[
            Icon(state.icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
          ],
          if (state.label != null)
            Text(
              state.label!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
        ],
      ),
    );
  }
}

class _IconFlash extends StatelessWidget {
  const _IconFlash({required this.state});
  final GestureFeedbackState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 0.5,
            ),
          ),
          child: state.icon != null
              ? Icon(state.icon, color: Colors.white, size: 44)
              : null,
        ),
        if (state.label != null) ...[
          const SizedBox(height: 8),
          Text(
            state.label!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
