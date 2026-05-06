import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 视频缓冲 / 打开阶段中央 loading 动画。
///
/// 设计来自 niuma-player-assets/sdk/assets/loading/loading_animated.svg：
///   - 外圈一只 bug 绕中心旋转（2s/圈）
///   - 中央牛马头 + 闪烁的 ×× 死机眼（1.2s 周期）
///   - 底下三个橙点依次 0.3s 错位脉动（1.2s 周期）
///
/// flutter_svg 不渲染 SMIL，所以这里用 [CustomPainter] 在 Dart 侧画并真动起来。
class NiumaLoadingIndicator extends StatefulWidget {
  const NiumaLoadingIndicator({super.key, this.size = 96});

  final double size;

  @override
  State<NiumaLoadingIndicator> createState() => _NiumaLoadingIndicatorState();
}

class _NiumaLoadingIndicatorState extends State<NiumaLoadingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _pulse]),
        builder: (_, __) => CustomPaint(
          painter: _NiumaLoadingPainter(
            spin: _spin.value,
            pulse: _pulse.value,
          ),
        ),
      ),
    );
  }
}

class _NiumaLoadingPainter extends CustomPainter {
  _NiumaLoadingPainter({required this.spin, required this.pulse});

  /// 0..1 持续旋转，bug 旋转角 = spin * 2π。
  final double spin;

  /// 0..1 1.2s 周期，眼睛闪烁 + 三点脉动共用。
  final double pulse;

  // 资源包品牌色（design-tokens.json）
  static const _brown = Color(0xFF854F0B); // accent
  static const _orange = Color(0xFFEF9F27); // primary
  static const _yellow = Color(0xFFFAC775); // primary_light
  static const _ink = Color(0xFF1A1410); // bg_dark / text_on_light

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final scale = size.width / 200.0;
    canvas.scale(scale);

    _drawBug(canvas);
    _drawNiumaHead(canvas);
    _drawDots(canvas);

    canvas.restore();
  }

  void _drawBug(Canvas canvas) {
    canvas.save();
    canvas.translate(100, 100);
    canvas.rotate(spin * 2 * math.pi);
    canvas.translate(0, -70); // bug 在 (0,-70) ≈ 原 SVG 中 (100,30)

    final body = Paint()..color = _ink;
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 20, height: 12),
      body,
    );

    final leg = Paint()
      ..color = _ink
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-7, -5), const Offset(-13, -12), leg);
    canvas.drawLine(const Offset(7, -5), const Offset(13, -12), leg);
    canvas.drawLine(const Offset(-9, 0), const Offset(-15, 0), leg);
    canvas.drawLine(const Offset(9, 0), const Offset(15, 0), leg);

    canvas.restore();
  }

  void _drawNiumaHead(Canvas canvas) {
    canvas.save();
    canvas.translate(100, 100);

    // 牛角
    final hornFill = Paint()..color = _brown;
    final leftHorn = Path()
      ..moveTo(-32, -22)
      ..lineTo(-42, -40)
      ..lineTo(-28, -30)
      ..close();
    final rightHorn = Path()
      ..moveTo(32, -22)
      ..lineTo(42, -40)
      ..lineTo(28, -30)
      ..close();
    canvas.drawPath(leftHorn, hornFill);
    canvas.drawPath(rightHorn, hornFill);

    // 头（圆角矩形）
    final head = Paint()..color = _yellow;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-30, -22, 60, 60),
        const Radius.circular(22),
      ),
      head,
    );

    // 三撮刘海
    final tuft1 = Path()
      ..moveTo(-15, -22)
      ..lineTo(-12, -30)
      ..lineTo(-9, -22)
      ..close();
    final tuft2 = Path()
      ..moveTo(0, -25)
      ..lineTo(3, -33)
      ..lineTo(6, -25)
      ..close();
    final tuft3 = Path()
      ..moveTo(9, -22)
      ..lineTo(12, -30)
      ..lineTo(15, -22)
      ..close();
    canvas.drawPath(tuft1, hornFill);
    canvas.drawPath(tuft2, hornFill);
    canvas.drawPath(tuft3, hornFill);

    // 闪烁的 ×× 死机眼（opacity 1 → 0.3 → 1）
    final eyeOpacity =
        1.0 - 0.7 * math.sin(pulse * math.pi).abs(); // 0.3..1.0
    final eye = Paint()
      ..color = _ink.withValues(alpha: eyeOpacity)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    // 左眼 ×
    canvas.drawLine(const Offset(-16, -3), const Offset(-10, 3), eye);
    canvas.drawLine(const Offset(-16, 3), const Offset(-10, -3), eye);
    // 右眼 ×
    canvas.drawLine(const Offset(10, -3), const Offset(16, 3), eye);
    canvas.drawLine(const Offset(10, 3), const Offset(16, -3), eye);

    // 嘴
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-5, 13, 10, 5),
        const Radius.circular(2.5),
      ),
      hornFill,
    );

    // 流口水
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 26), width: 6, height: 4),
      Paint()..color = _ink,
    );

    canvas.restore();
  }

  void _drawDots(Canvas canvas) {
    canvas.save();
    canvas.translate(100, 170);

    // 三点错位 0.3s（即 phase 偏移 0.25），各自走 0.3 → 1 → 0.3。
    for (var i = 0; i < 3; i++) {
      final phase = (pulse + i * 0.25) % 1.0;
      // 0..0.5 升，0.5..1 降；用 sin 平滑
      final t = math.sin(phase * math.pi); // 0..1..0
      final opacity = 0.3 + 0.7 * t;
      canvas.drawCircle(
        Offset(-12.0 + i * 12.0, 0),
        3,
        Paint()..color = _orange.withValues(alpha: opacity),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_NiumaLoadingPainter old) =>
      old.spin != spin || old.pulse != pulse;
}
