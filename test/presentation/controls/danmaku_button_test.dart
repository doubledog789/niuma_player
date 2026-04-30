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

  testWidgets('点击不响应——IgnorePointer 包裹图标，按钮自身无 enabled InkWell',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DanmakuButton()),
    ));

    expect(find.byType(DanmakuButton), findsOneWidget);
    // 严格断言：按钮子树里必须有一个 ignoring=true 的 IgnorePointer——
    // Tooltip 自己也用 IgnorePointer 但 ignoring=false，所以按
    // ignoring 字段筛。防止后续 refactor 误删 disabled 视觉。
    final ignoringTrue = find.descendant(
      of: find.byType(DanmakuButton),
      matching: find.byWidgetPredicate(
        (w) => w is IgnorePointer && w.ignoring == true,
      ),
    );
    expect(
      ignoringTrue,
      findsOneWidget,
      reason: 'DanmakuButton 应当渲染 ignoring=true 的 IgnorePointer',
    );
    // 按钮子树内也不应有 InkWell（避免误以为可点）。
    expect(
      find.descendant(
        of: find.byType(DanmakuButton),
        matching: find.byType(InkWell),
      ),
      findsNothing,
      reason: 'M9 disabled 阶段不应渲染可交互的 InkWell',
    );
    await tester.tap(find.byType(DanmakuButton), warnIfMissed: false);
    await tester.pump();
  });
}
