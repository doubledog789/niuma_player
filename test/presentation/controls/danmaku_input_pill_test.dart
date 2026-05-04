import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/danmaku_input_pill.dart';

void main() {
  testWidgets('点击触发 onTap', (t) async {
    bool tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DanmakuInputPill(onTap: () => tapped = true),
      ),
    ));
    await t.tap(find.byType(DanmakuInputPill));
    expect(tapped, isTrue);
  });

  testWidgets('onTap 为 null 时点击不抛异常', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: DanmakuInputPill(onTap: null)),
    ));
    await t.tap(find.byType(DanmakuInputPill));
  });
}
