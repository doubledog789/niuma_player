import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/speed_selector.dart';

import 'fake_controller.dart';

void main() {
  testWidgets('点击触发 popup 列出 0.5/1.0/1.5/2.0', (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SpeedSelector(controller: ctl))),
    ));

    await tester.tap(find.byType(SpeedSelector));
    await tester.pumpAndSettle();

    expect(find.text('0.5x'), findsOneWidget);
    expect(find.text('1.0x'), findsOneWidget);
    expect(find.text('1.5x'), findsOneWidget);
    expect(find.text('2.0x'), findsOneWidget);
  });

  testWidgets('选中某档调 controller.setPlaybackSpeed', (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SpeedSelector(controller: ctl))),
    ));

    await tester.tap(find.byType(SpeedSelector));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1.5x'));
    await tester.pumpAndSettle();

    expect(ctl.lastSpeed, 1.5);
  });
}
