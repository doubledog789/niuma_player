import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/pip_action.dart';

import 'fake_controller.dart';

void main() {
  testWidgets('PipAction 渲染「画中画」中文 label', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: PipAction(controller: ctl)),
    ));
    expect(find.text('画中画'), findsOneWidget);
  });

  testWidgets('PipAction onTap callback 点击触发', (t) async {
    final ctl = FakeNiumaPlayerController();
    bool tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PipAction(controller: ctl, onTap: () => tapped = true),
      ),
    ));
    await t.tap(find.byType(PipAction));
    expect(tapped, isTrue);
  });
}
