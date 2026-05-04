import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/niuma_player_theme.dart';

void main() {
  group('NiumaPlayerTheme defaults', () {
    test('默认实例字段为文档默认值', () {
      const theme = NiumaPlayerTheme();

      expect(theme.accentColor, isNull);
      expect(theme.iconColor, Colors.white);
      expect(theme.iconSize, 24);
      expect(theme.bigIconSize, 36);
      expect(
        theme.controlBarPadding,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      );
      expect(theme.scrubBarHeight, 4);
      expect(theme.scrubBarThumbRadius, 6);
      expect(theme.scrubBarThumbRadiusActive, 9);
      expect(theme.bufferedFillColor, isNull);
      expect(theme.thumbnailPreviewSize, const Size(160, 90));
      expect(theme.fadeInDuration, const Duration(milliseconds: 200));
      expect(
        theme.controlsBackgroundGradient,
        const [Colors.transparent, Colors.black87],
      );
      expect(theme.timeTextStyle, isA<TextStyle>());
    });
  });

  group('NiumaPlayerTheme equality', () {
    test('相同字段的两个实例 == true 且 hashCode 相同', () {
      const a = NiumaPlayerTheme();
      const b = NiumaPlayerTheme();

      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('一个字段差异即 == false', () {
      const a = NiumaPlayerTheme();
      const b = NiumaPlayerTheme(iconSize: 32);

      expect(a == b, isFalse);
    });

    test('全部 13 字段任一不同都被检测出', () {
      const base = NiumaPlayerTheme();
      final variations = <NiumaPlayerTheme>[
        const NiumaPlayerTheme(accentColor: Colors.red),
        const NiumaPlayerTheme(iconColor: Colors.black),
        const NiumaPlayerTheme(iconSize: 99),
        const NiumaPlayerTheme(bigIconSize: 99),
        const NiumaPlayerTheme(controlBarPadding: EdgeInsets.zero),
        const NiumaPlayerTheme(scrubBarHeight: 99),
        const NiumaPlayerTheme(scrubBarThumbRadius: 99),
        const NiumaPlayerTheme(scrubBarThumbRadiusActive: 99),
        const NiumaPlayerTheme(bufferedFillColor: Colors.green),
        const NiumaPlayerTheme(thumbnailPreviewSize: Size(99, 99)),
        const NiumaPlayerTheme(fadeInDuration: Duration(seconds: 99)),
        const NiumaPlayerTheme(controlsBackgroundGradient: [Colors.red]),
        const NiumaPlayerTheme(timeTextStyle: TextStyle(fontSize: 99)),
      ];
      for (final v in variations) {
        expect(v == base, isFalse, reason: '差异实例应当与默认实例不相等：$v');
      }
    });
  });

  group('NiumaPlayerThemeData InheritedWidget', () {
    testWidgets('updateShouldNotify 在 theme 变化时返回 true', (tester) async {
      const a = NiumaPlayerTheme();
      const b = NiumaPlayerTheme(iconSize: 32);

      final widgetA = NiumaPlayerThemeData(
        data: a,
        child: const SizedBox(),
      );
      final widgetB = NiumaPlayerThemeData(
        data: b,
        child: const SizedBox(),
      );

      expect(widgetB.updateShouldNotify(widgetA), isTrue);
    });

    testWidgets('updateShouldNotify 在 theme 相同时返回 false', (tester) async {
      const a = NiumaPlayerTheme();
      const b = NiumaPlayerTheme();

      final widgetA = NiumaPlayerThemeData(
        data: a,
        child: const SizedBox(),
      );
      final widgetB = NiumaPlayerThemeData(
        data: b,
        child: const SizedBox(),
      );

      expect(widgetB.updateShouldNotify(widgetA), isFalse);
    });

    testWidgets('NiumaPlayerTheme.of(context) 拿到注入的 theme', (tester) async {
      const custom = NiumaPlayerTheme(iconSize: 48);
      late NiumaPlayerTheme picked;

      await tester.pumpWidget(
        NiumaPlayerThemeData(
          data: custom,
          child: Builder(
            builder: (context) {
              picked = NiumaPlayerTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(picked.iconSize, 48);
      expect(picked, custom);
    });

    testWidgets('NiumaPlayerTheme.of(context) 在没有 inherited 时返回默认实例',
        (tester) async {
      late NiumaPlayerTheme picked;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            picked = NiumaPlayerTheme.of(context);
            return const SizedBox();
          },
        ),
      );

      expect(picked, const NiumaPlayerTheme());
    });
  });

  group('M16 fields', () {
    test('primaryAccent 默认 Color(0xFFFB7299) (B 站粉)', () {
      const theme = NiumaPlayerTheme();
      expect(theme.primaryAccent, const Color(0xFFFB7299));
    });

    test('actionIconSize 默认 20', () {
      const theme = NiumaPlayerTheme();
      expect(theme.actionIconSize, 20);
    });

    test('centerPlayPauseSize 默认 48', () {
      const theme = NiumaPlayerTheme();
      expect(theme.centerPlayPauseSize, 48);
    });

    test('chapterMarkColor 默认半透明白', () {
      const theme = NiumaPlayerTheme();
      expect(theme.chapterMarkColor, const Color(0x99FFFFFF));
    });

    test('actionLabelStyle 默认 8px white', () {
      const theme = NiumaPlayerTheme();
      expect(theme.actionLabelStyle.fontSize, 8);
      expect(theme.actionLabelStyle.color, const Color(0xFFFFFFFF));
    });

    test('自定义 primaryAccent 后字段保留', () {
      const customAccent = Color(0xFF00FF00);
      const theme = NiumaPlayerTheme(primaryAccent: customAccent);
      expect(theme.primaryAccent, customAccent);
    });
  });
}
