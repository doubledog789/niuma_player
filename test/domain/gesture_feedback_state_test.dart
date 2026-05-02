import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/gesture_feedback_state.dart';
import 'package:niuma_player/src/domain/gesture_kind.dart';

void main() {
  test('默认值', () {
    const s = GestureFeedbackState(kind: GestureKind.doubleTap, progress: 0.5);
    expect(s.kind, GestureKind.doubleTap);
    expect(s.progress, 0.5);
    expect(s.label, isNull);
    expect(s.icon, isNull);
  });

  test('equality 全字段覆盖', () {
    const a = GestureFeedbackState(
      kind: GestureKind.volume,
      progress: 0.6,
      label: '60%',
      icon: Icons.volume_up,
    );
    const b = GestureFeedbackState(
      kind: GestureKind.volume,
      progress: 0.6,
      label: '60%',
      icon: Icons.volume_up,
    );
    const c = GestureFeedbackState(kind: GestureKind.volume, progress: 0.7);
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(a, isNot(equals(c)));
  });

  test('copyWith 单字段更新保留其他', () {
    const a = GestureFeedbackState(
      kind: GestureKind.brightness,
      progress: 0.5,
      label: '50%',
    );
    final b = a.copyWith(progress: 0.7);
    expect(b.progress, 0.7);
    expect(b.kind, GestureKind.brightness);
    expect(b.label, '50%');
  });

  test('copyWith() 无参数返回等值', () {
    const a = GestureFeedbackState(kind: GestureKind.doubleTap, progress: 1.0);
    expect(a.copyWith(), equals(a));
  });
}
