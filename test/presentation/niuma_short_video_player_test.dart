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
}
