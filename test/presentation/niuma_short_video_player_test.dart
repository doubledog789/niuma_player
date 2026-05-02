// test/presentation/niuma_short_video_player_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

import 'controls/fake_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mounts without crash', (tester) async {
    final c = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoPlayer(controller: c),
      ),
    ));

    expect(find.byType(NiumaShortVideoPlayer), findsOneWidget);
  });

  testWidgets('包含 NiumaPlayerView', (tester) async {
    final c = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoPlayer(controller: c),
      ),
    ));

    expect(
      find.descendant(
        of: find.byType(NiumaShortVideoPlayer),
        matching: find.byType(NiumaPlayerView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('包含 NiumaShortVideoProgressBar', (tester) async {
    final c = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoPlayer(controller: c),
      ),
    ));

    expect(find.byType(NiumaShortVideoProgressBar), findsOneWidget);
  });

  group('isActive 协调', () {
    testWidgets('isActive=false 初始化时调 controller.pause', (tester) async {
      final c = FakeNiumaPlayerController();
      c.value = c.value.copyWith(phase: PlayerPhase.playing);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c, isActive: false),
        ),
      ));
      await tester.pump();

      // initState（postFrame）应触发 pause
      expect(c.pauseCount, greaterThanOrEqualTo(1));
    });

    testWidgets('isActive true→false 切换调 pause', (tester) async {
      final c = FakeNiumaPlayerController();
      c.value = c.value.copyWith(phase: PlayerPhase.playing);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c, isActive: true),
        ),
      ));
      final beforeSwitch = c.pauseCount;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c, isActive: false),
        ),
      ));
      await tester.pump();

      expect(c.pauseCount, greaterThan(beforeSwitch));
    });

    testWidgets('isActive false→true 切换调 play', (tester) async {
      final c = FakeNiumaPlayerController();
      c.value = c.value.copyWith(phase: PlayerPhase.paused);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c, isActive: false),
        ),
      ));
      final beforeSwitch = c.playCount;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c, isActive: true),
        ),
      ));
      await tester.pump();

      expect(c.playCount, greaterThan(beforeSwitch));
    });
  });
}
