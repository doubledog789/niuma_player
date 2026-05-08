import 'package:flutter/material.dart';

import 'package:niuma_player/src/domain/gesture_feedback_state.dart';
import 'package:niuma_player/src/domain/gesture_kind.dart';
import 'package:niuma_player/src/presentation/controls/niuma_sdk_icon.dart';
import 'package:niuma_player/src/presentation/shared/glass_card.dart';

// 牛马品牌色（design-tokens.json brand.primary / primary_light）
const _brandOrange = Color(0xFFEF9F27);
const _brandLight = Color(0xFFFAC775);

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

/// 抖音 / B 站风的 seek HUD——拖动快进 / 快退时浮在屏幕中央。
///
/// 视觉重点：
/// - 顶部 brand 色 delta tag (`+10s` / `-10s`) + 方向箭头
/// - 中央超大字 target 时间（`02:45`）—— 用户最关心的"我要 seek 到哪"
/// - 底部 dim 颜色 total 时长 (`/ 09:56`)
/// - 底部细进度条（thin brand 色 + dim 灰底）作为"在视频时间轴的哪里"的视觉锚点
///
/// 之前的 _SeekCard 只是"标签 + 200px 灰条"，信息平铺没层次；新设计用大小、
/// 颜色、间距引导视线先看 delta → 再看 target → 再看 total + 进度。
class _SeekCard extends StatelessWidget {
  const _SeekCard({required this.state});
  final GestureFeedbackState state;

  /// 解析 [NiumaGestureLayer] 拼的 label 格式：`+10s / 02:45 / 09:56`，
  /// 拆成 (delta, target, total) 三段。容错：少于三段时部分返 null。
  static (String?, String?, String?) _parseSeekLabel(String? label) {
    if (label == null) return (null, null, null);
    final parts = label.split(' / ');
    if (parts.length >= 3) return (parts[0], parts[1], parts[2]);
    if (parts.length == 2) return (parts[0], parts[1], null);
    return (parts[0], null, null);
  }

  @override
  Widget build(BuildContext context) {
    final (delta, target, total) = _parseSeekLabel(state.label);
    // delta tag 以 '+' 开头视为快进，否则 '-' / '0' 视为快退或不变。
    // 同时 fallback 到 icon——`Icons.fast_forward` 的 codePoint 在 NiumaGestureLayer
    // 给的是 `seekDeltaMs >= 0` 的分支固定值，跟 delta 符号同步。
    final isForward = (delta?.startsWith('+') ?? true) &&
        (delta == null || !delta.startsWith('-'));

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部：方向箭头 + delta tag（brand 色）
            if (delta != null && delta.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isForward ? Icons.fast_forward : Icons.fast_rewind,
                    color: _brandOrange,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    delta,
                    style: const TextStyle(
                      color: _brandOrange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            if (delta != null && delta.isNotEmpty) const SizedBox(height: 6),
            // 中央：target 时间（大字）
            if (target != null)
              Text(
                target,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  height: 1.0,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            // 底部：total 时长（小字 dim）
            if (total != null) ...[
              const SizedBox(height: 4),
              Text(
                '/ $total',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            // 进度锚点（细线）
            const SizedBox(height: 10),
            _ProgressBar(
              value: state.progress,
              color: _brandOrange,
              width: 160,
            ),
          ],
        ),
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
    // 亮度走牛马 highlight（暖金 #FAC775），音量走牛马 primary（橙 #EF9F27）
    final accent = isBrightness ? _brandLight : _brandOrange;
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.iconAsset != null) ...[
            NiumaSdkIcon(asset: state.iconAsset!, color: accent, size: 36),
            const SizedBox(height: 10),
          ] else if (state.icon != null) ...[
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
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      radius: 999,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.iconAsset != null) ...[
            NiumaSdkIcon(
              asset: state.iconAsset!,
              color: _brandOrange,
              size: 18,
            ),
            const SizedBox(width: 6),
          ] else if (state.icon != null) ...[
            Icon(state.icon, color: _brandOrange, size: 18),
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
          child: state.iconAsset != null
              ? Center(
                  child: NiumaSdkIcon(
                    asset: state.iconAsset!,
                    color: _brandOrange,
                    size: 44,
                  ),
                )
              : (state.icon != null
                  ? Icon(state.icon, color: _brandOrange, size: 44)
                  : null),
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
