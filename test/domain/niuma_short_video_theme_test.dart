// test/domain/niuma_short_video_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/niuma_short_video_theme.dart';

void main() {
  group('NiumaShortVideoTheme', () {
    test('defaults() 字段值', () {
      final t = NiumaShortVideoTheme.defaults();
      expect(t.progressIdleHeight, 1.5);
      expect(t.progressActiveHeight, 3.5);
      // 牛马橙 #EF9F27 作为 played / thumb / pause icon 默认色，
      // 替代之前一律白色的设计。
      expect(t.progressPlayedColor, const Color(0xFFEF9F27));
      expect(t.progressTrackColor, Colors.white.withValues(alpha: 0.18));
      expect(t.progressBufferedColor, Colors.white.withValues(alpha: 0.3));
      expect(t.progressThumbColor, const Color(0xFFEF9F27));
      expect(t.progressThumbRadius, 6.0);
      expect(t.pauseIndicatorBackgroundColor,
          Colors.black.withValues(alpha: 0.5));
      expect(t.pauseIndicatorIconColor, const Color(0xFFEF9F27));
      expect(t.pauseIndicatorSize, 56);
      expect(t.pauseIndicatorIconSize, 56);
      expect(t.scrubLabelTextColor, Colors.white);
      expect(t.scrubLabelBackgroundColor,
          Colors.black.withValues(alpha: 0.55));
    });

    test('相同字段 == true 且 hashCode 相同', () {
      final a = NiumaShortVideoTheme.defaults();
      final b = NiumaShortVideoTheme.defaults();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      // identical short-circuit
      expect(a, equals(a));
    });

    test('每个字段不同都被检测出 (== false)', () {
      // 13 字段任一变化都应让 == 返回 false。
      final base = NiumaShortVideoTheme.defaults();
      expect(base, isNot(equals(base.copyWith(progressIdleHeight: 2))));
      expect(base, isNot(equals(base.copyWith(progressActiveHeight: 4))));
      expect(base, isNot(equals(base.copyWith(progressPlayedColor: Colors.red))));
      expect(base, isNot(equals(base.copyWith(progressTrackColor: Colors.red))));
      expect(base, isNot(equals(base.copyWith(progressBufferedColor: Colors.red))));
      expect(base, isNot(equals(base.copyWith(progressThumbColor: Colors.red))));
      expect(base, isNot(equals(base.copyWith(progressThumbRadius: 8))));
      expect(base, isNot(equals(base.copyWith(pauseIndicatorBackgroundColor: Colors.red))));
      expect(base, isNot(equals(base.copyWith(pauseIndicatorIconColor: Colors.red))));
      expect(base, isNot(equals(base.copyWith(pauseIndicatorSize: 100))));
      expect(base, isNot(equals(base.copyWith(pauseIndicatorIconSize: 60))));
      expect(base, isNot(equals(base.copyWith(scrubLabelTextColor: Colors.red))));
      expect(base, isNot(equals(base.copyWith(scrubLabelBackgroundColor: Colors.red))));
    });

    test('copyWith 不传字段 → 沿用原值', () {
      final a = NiumaShortVideoTheme.defaults();
      final b = a.copyWith();
      expect(a, equals(b));
    });
  });
}
