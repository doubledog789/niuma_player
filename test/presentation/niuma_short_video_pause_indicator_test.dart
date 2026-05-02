// test/presentation/niuma_short_video_pause_indicator_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/niuma_short_video_theme.dart';
import 'package:niuma_player/src/presentation/niuma_short_video_pause_indicator.dart';

void main() {
  testWidgets('渲染圆形容器 + play_arrow_rounded 图标', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoPauseIndicator(
          theme: NiumaShortVideoTheme.defaults(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('容器尺寸 == theme.pauseIndicatorSize', (tester) async {
    final theme = NiumaShortVideoTheme.defaults()
        .copyWith(pauseIndicatorSize: 120);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoPauseIndicator(theme: theme),
      ),
    ));
    await tester.pumpAndSettle();
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(NiumaShortVideoPauseIndicator),
        matching: find.byType(Container),
      ),
    );
    final box = container.constraints;
    expect(box, const BoxConstraints.tightFor(width: 120, height: 120));
  });

  testWidgets('Icon 尺寸 == theme.pauseIndicatorIconSize', (tester) async {
    final theme = NiumaShortVideoTheme.defaults()
        .copyWith(pauseIndicatorIconSize: 80);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoPauseIndicator(theme: theme),
      ),
    ));
    await tester.pumpAndSettle();
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.size, 80);
  });

  testWidgets('Icon 颜色 == theme.pauseIndicatorIconColor', (tester) async {
    final theme = NiumaShortVideoTheme.defaults()
        .copyWith(pauseIndicatorIconColor: const Color(0xFF112233));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoPauseIndicator(theme: theme),
      ),
    ));
    await tester.pumpAndSettle();
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, const Color(0xFF112233));
  });

  testWidgets('容器背景 == theme.pauseIndicatorBackgroundColor', (tester) async {
    final theme = NiumaShortVideoTheme.defaults()
        .copyWith(pauseIndicatorBackgroundColor: const Color(0xFFAABBCC));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoPauseIndicator(theme: theme),
      ),
    ));
    await tester.pumpAndSettle();
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(NiumaShortVideoPauseIndicator),
        matching: find.byType(Container),
      ),
    );
    final dec = container.decoration as BoxDecoration;
    expect(dec.color, const Color(0xFFAABBCC));
    expect(dec.shape, BoxShape.circle);
  });

  testWidgets('入场带 AnimatedScale', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoPauseIndicator(
          theme: NiumaShortVideoTheme.defaults(),
        ),
      ),
    ));
    expect(find.byType(AnimatedScale), findsOneWidget);
  });
}
