import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/presentation/controls/play_pause_button.dart';

import 'fake_controller.dart';

void main() {
  testWidgets('phase=playing 显示 pause 图标', (tester) async {
    final ctl = FakeNiumaPlayerController();
    ctl.value =
        NiumaPlayerValue.uninitialized().copyWith(phase: PlayerPhase.playing);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PlayPauseButton(controller: ctl)),
    ));

    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('phase=paused 显示 play 图标', (tester) async {
    final ctl = FakeNiumaPlayerController();
    ctl.value =
        NiumaPlayerValue.uninitialized().copyWith(phase: PlayerPhase.paused);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PlayPauseButton(controller: ctl)),
    ));

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets('phase=playing 时点击调 controller.pause()', (tester) async {
    final ctl = FakeNiumaPlayerController();
    ctl.value =
        NiumaPlayerValue.uninitialized().copyWith(phase: PlayerPhase.playing);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PlayPauseButton(controller: ctl)),
    ));

    await tester.tap(find.byType(PlayPauseButton));
    await tester.pump();

    expect(ctl.pauseCount, 1);
    expect(ctl.playCount, 0);
  });

  testWidgets('phase=paused 时点击调 controller.play()', (tester) async {
    final ctl = FakeNiumaPlayerController();
    ctl.value =
        NiumaPlayerValue.uninitialized().copyWith(phase: PlayerPhase.paused);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PlayPauseButton(controller: ctl)),
    ));

    await tester.tap(find.byType(PlayPauseButton));
    await tester.pump();

    expect(ctl.playCount, 1);
    expect(ctl.pauseCount, 0);
  });
}
