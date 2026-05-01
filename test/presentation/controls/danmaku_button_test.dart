import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/orchestration/danmaku_models.dart';
import 'package:niuma_player/src/presentation/niuma_danmaku_controller.dart';
import 'package:niuma_player/src/presentation/niuma_danmaku_scope.dart';

void main() {
  testWidgets('显式 controller：tap → toggle visible', (tester) async {
    final c = NiumaDanmakuController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DanmakuButton(danmakuController: c)),
    ));
    expect(c.settings.visible, isTrue);
    await tester.tap(find.byType(DanmakuButton));
    await tester.pump();
    expect(c.settings.visible, isFalse);
    c.dispose();
  });

  testWidgets('scope 注入：tap → toggle', (tester) async {
    final c = NiumaDanmakuController();
    await tester.pumpWidget(MaterialApp(
      home: NiumaDanmakuScope(
        controller: c,
        child: const Scaffold(body: DanmakuButton()),
      ),
    ));
    await tester.tap(find.byType(DanmakuButton));
    await tester.pump();
    expect(c.settings.visible, isFalse);
    c.dispose();
  });

  testWidgets('显式参数 > scope（前者优先）', (tester) async {
    final cExplicit = NiumaDanmakuController();
    final cScope = NiumaDanmakuController();
    await tester.pumpWidget(MaterialApp(
      home: NiumaDanmakuScope(
        controller: cScope,
        child: Scaffold(body: DanmakuButton(danmakuController: cExplicit)),
      ),
    ));
    await tester.tap(find.byType(DanmakuButton));
    await tester.pump();
    expect(cExplicit.settings.visible, isFalse);
    expect(cScope.settings.visible, isTrue, reason: '显式优先，scope 不应被改');
    cExplicit.dispose();
    cScope.dispose();
  });

  testWidgets('都没有 controller → IgnorePointer ignoring=true', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DanmakuButton()),
    ));
    final ignoringTrue = find.descendant(
      of: find.byType(DanmakuButton),
      matching: find.byWidgetPredicate(
        (w) => w is IgnorePointer && w.ignoring == true,
      ),
    );
    expect(ignoringTrue, findsOneWidget);
  });
}
