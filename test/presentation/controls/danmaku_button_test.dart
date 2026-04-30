import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/danmaku_button.dart';

void main() {
  testWidgets('disabled 视觉——降低 opacity / 灰色', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DanmakuButton()),
    ));

    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    final opacityWidget = tester.widget<Opacity>(
      find.ancestor(
        of: find.byIcon(Icons.chat_bubble_outline),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacityWidget.opacity, lessThan(1.0));
  });

  testWidgets('Tooltip message="M11 启用"', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DanmakuButton()),
    ));

    final tooltip = tester.widget<Tooltip>(
      find.byType(Tooltip),
    );
    expect(tooltip.message, 'M11 启用');
  });

  testWidgets('点击不响应', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DanmakuButton()),
    ));

    expect(find.byType(DanmakuButton), findsOneWidget);
    await tester.tap(find.byType(DanmakuButton));
    await tester.pump();
    // M9 阶段无任何逻辑——这里只确保 tap 不抛。
  });
}
