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
      expect(t.progressPlayedColor, Colors.white);
      expect(t.progressTrackColor, Colors.white.withValues(alpha: 0.18));
      expect(t.progressBufferedColor, Colors.white.withValues(alpha: 0.3));
      expect(t.progressThumbColor, Colors.white);
      expect(t.progressThumbRadius, 6.0);
      expect(t.pauseIndicatorBackgroundColor,
          Colors.black.withValues(alpha: 0.5));
      expect(t.pauseIndicatorIconColor, Colors.white);
      expect(t.pauseIndicatorSize, 96);
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
    });

    test('每个字段不同都被检测出 (== false)', () {
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
