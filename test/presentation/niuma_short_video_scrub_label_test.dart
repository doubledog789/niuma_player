// test/presentation/niuma_short_video_scrub_label_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/niuma_short_video_theme.dart';
import 'package:niuma_player/src/presentation/niuma_short_video_scrub_label.dart';

void main() {
  testWidgets('渲染 mm:ss / mm:ss 格式', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoScrubLabel(
          position: const Duration(seconds: 15),
          duration: const Duration(minutes: 3, seconds: 42),
          theme: NiumaShortVideoTheme.defaults(),
        ),
      ),
    ));
    expect(find.text('00:15 / 03:42'), findsOneWidget);
  });

  testWidgets('小时数 ≥ 1 时格式 H:mm:ss', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoScrubLabel(
          position: const Duration(hours: 1, minutes: 2, seconds: 3),
          duration: const Duration(hours: 2),
          theme: NiumaShortVideoTheme.defaults(),
        ),
      ),
    ));
    expect(find.text('1:02:03 / 2:00:00'), findsOneWidget);
  });

  testWidgets('使用 theme.scrubLabelBackgroundColor', (tester) async {
    final theme = NiumaShortVideoTheme.defaults().copyWith(
      scrubLabelBackgroundColor: const Color(0xFF112233),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoScrubLabel(
          position: Duration.zero,
          duration: const Duration(seconds: 10),
          theme: theme,
        ),
      ),
    ));
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(NiumaShortVideoScrubLabel),
        matching: find.byType(Container),
      ),
    );
    final dec = container.decoration as BoxDecoration;
    expect(dec.color, const Color(0xFF112233));
  });

  testWidgets('使用 theme.scrubLabelTextColor', (tester) async {
    final theme = NiumaShortVideoTheme.defaults().copyWith(
      scrubLabelTextColor: const Color(0xFFAABBCC),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoScrubLabel(
          position: Duration.zero,
          duration: const Duration(seconds: 10),
          theme: theme,
        ),
      ),
    ));
    final text = tester.widget<Text>(find.text('00:00 / 00:10'));
    expect(text.style?.color, const Color(0xFFAABBCC));
  });
}
