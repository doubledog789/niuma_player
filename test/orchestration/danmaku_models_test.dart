import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/danmaku_models.dart';

void main() {
  group('DanmakuItem', () {
    test('默认值', () {
      const it = DanmakuItem(position: Duration(seconds: 5), text: '666');
      expect(it.fontSize, 20);
      expect(it.color, const Color(0xFFFFFFFF));
      expect(it.mode, DanmakuMode.scroll);
      expect(it.pool, isNull);
      expect(it.metadata, isNull);
    });

    test('equality 基于全部字段', () {
      const a = DanmakuItem(position: Duration(seconds: 5), text: '666');
      const b = DanmakuItem(position: Duration(seconds: 5), text: '666');
      const c = DanmakuItem(position: Duration(seconds: 5), text: '777');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith', () {
      const a = DanmakuItem(position: Duration(seconds: 5), text: '666');
      final b = a.copyWith(text: '777');
      expect(b.text, '777');
      expect(b.position, a.position);
    });
  });

  group('DanmakuMode', () {
    test('三个值齐全', () {
      expect(DanmakuMode.values, hasLength(3));
      expect(DanmakuMode.values,
          containsAll([DanmakuMode.scroll, DanmakuMode.topFixed, DanmakuMode.bottomFixed]));
    });
  });

  group('DanmakuSettings', () {
    test('默认值', () {
      const s = DanmakuSettings();
      expect(s.visible, isTrue);
      expect(s.fontScale, 1.0);
      expect(s.opacity, 1.0);
      expect(s.displayAreaPercent, 1.0);
      expect(s.bucketSize, const Duration(seconds: 60));
      expect(s.scrollDuration, const Duration(seconds: 10));
      expect(s.fixedDuration, const Duration(seconds: 5));
    });

    test('copyWith + equality', () {
      const a = DanmakuSettings();
      final b = a.copyWith(opacity: 0.5);
      expect(b.opacity, 0.5);
      expect(b.visible, isTrue);
      expect(a, isNot(equals(b)));
      expect(a.copyWith(), equals(a));
    });
  });
}
