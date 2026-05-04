import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/cast_action.dart';

import 'fake_controller.dart';

void main() {
  testWidgets('CastAction 渲染「投屏」中文 label', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: CastAction(controller: ctl)),
    ));
    expect(find.text('投屏'), findsOneWidget);
  });

  testWidgets('CastAction onTap callback 点击触发', (t) async {
    final ctl = FakeNiumaPlayerController();
    bool tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CastAction(controller: ctl, onTap: () => tapped = true),
      ),
    ));
    await t.tap(find.byType(CastAction));
    expect(tapped, isTrue);
  });
}
