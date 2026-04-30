import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/presentation/controls/time_display.dart';

import 'fake_controller.dart';

void main() {
  testWidgets('渲染 mm:ss / mm:ss 格式', (tester) async {
    final ctl = FakeNiumaPlayerController();
    ctl.value = NiumaPlayerValue.uninitialized().copyWith(
      phase: PlayerPhase.playing,
      position: const Duration(minutes: 1, seconds: 23),
      duration: const Duration(minutes: 5, seconds: 7),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TimeDisplay(controller: ctl)),
    ));

    expect(find.text('01:23 / 05:07'), findsOneWidget);
  });

  testWidgets('duration=0 时仍显示 00:00 / 00:00', (tester) async {
    final ctl = FakeNiumaPlayerController();
    ctl.value = NiumaPlayerValue.uninitialized();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TimeDisplay(controller: ctl)),
    ));

    expect(find.text('00:00 / 00:00'), findsOneWidget);
  });

  testWidgets('value 变化时文本随之更新', (tester) async {
    final ctl = FakeNiumaPlayerController();
    ctl.value = NiumaPlayerValue.uninitialized().copyWith(
      position: const Duration(seconds: 10),
      duration: const Duration(seconds: 100),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TimeDisplay(controller: ctl)),
    ));
    expect(find.text('00:10 / 01:40'), findsOneWidget);

    ctl.value = ctl.value.copyWith(position: const Duration(seconds: 50));
    await tester.pump();
    expect(find.text('00:50 / 01:40'), findsOneWidget);
  });
}
