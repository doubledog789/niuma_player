// test/presentation/niuma_short_video_progress_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/domain/niuma_short_video_theme.dart';
import 'package:niuma_player/src/presentation/niuma_short_video_progress_bar.dart';

import 'controls/fake_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, height: 400, child: child),
        ),
      );

  testWidgets('idle 状态高度 == theme.progressIdleHeight', (tester) async {
    final c = FakeNiumaPlayerController();
    final theme = NiumaShortVideoTheme.defaults().copyWith(progressIdleHeight: 2);

    await tester.pumpWidget(wrap(
      Align(
        alignment: Alignment.bottomCenter,
        child: NiumaShortVideoProgressBar(
          controller: c,
          theme: theme,
          onScrubStart: () {},
          onScrubUpdate: (_) {},
          onScrubEnd: () {},
        ),
      ),
    ));

    final bar = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    expect((bar.constraints?.maxHeight ?? 0), 2.0);
  });

  testWidgets('pointerDown → 调 onScrubStart + controller.pause + 高度变 active',
      (tester) async {
    final c = FakeNiumaPlayerController();
    var startCalls = 0;
    final theme = NiumaShortVideoTheme.defaults();

    await tester.pumpWidget(wrap(
      Align(
        alignment: Alignment.bottomCenter,
        child: NiumaShortVideoProgressBar(
          controller: c,
          theme: theme,
          onScrubStart: () => startCalls++,
          onScrubUpdate: (_) {},
          onScrubEnd: () {},
        ),
      ),
    ));

    final center = tester.getCenter(find.byType(NiumaShortVideoProgressBar));
    final gesture = await tester.startGesture(center);
    addTearDown(() async => gesture.up());
    await tester.pump(const Duration(milliseconds: 200));

    expect(startCalls, 1);
    final bar = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    expect((bar.constraints?.maxHeight ?? 0), theme.progressActiveHeight);
  });

  testWidgets('pointerMove → onScrubUpdate 拿到对应位置', (tester) async {
    final c = FakeNiumaPlayerController();
    c.value = c.value.copyWith(duration: const Duration(seconds: 100));

    Duration? lastUpdate;
    await tester.pumpWidget(wrap(
      Align(
        alignment: Alignment.bottomCenter,
        child: NiumaShortVideoProgressBar(
          controller: c,
          theme: NiumaShortVideoTheme.defaults(),
          onScrubStart: () {},
          onScrubUpdate: (d) => lastUpdate = d,
          onScrubEnd: () {},
        ),
      ),
    ));

    final start = tester.getTopLeft(find.byType(NiumaShortVideoProgressBar));
    final gesture = await tester.startGesture(
      Offset(start.dx + 100, start.dy + 12),
    );
    addTearDown(() async => gesture.up());
    await gesture.moveTo(Offset(start.dx + 200, start.dy + 12));
    await tester.pump();

    // 200/400 = 50% of 100s = 50s
    expect(lastUpdate?.inSeconds, 50);
  });

  testWidgets('pointerUp → seekTo + onScrubEnd', (tester) async {
    final c = FakeNiumaPlayerController();
    c.value = c.value.copyWith(duration: const Duration(seconds: 100));

    var endCalls = 0;
    await tester.pumpWidget(wrap(
      Align(
        alignment: Alignment.bottomCenter,
        child: NiumaShortVideoProgressBar(
          controller: c,
          theme: NiumaShortVideoTheme.defaults(),
          onScrubStart: () {},
          onScrubUpdate: (_) {},
          onScrubEnd: () => endCalls++,
        ),
      ),
    ));

    final barLeft =
        tester.getTopLeft(find.byType(NiumaShortVideoProgressBar));
    final gesture = await tester.startGesture(
      Offset(barLeft.dx + 100, barLeft.dy + 12),
    );
    await gesture.moveTo(Offset(barLeft.dx + 200, barLeft.dy + 12));
    await gesture.up();
    await tester.pump();

    expect(endCalls, 1);
    // 200 / 400 = 50% of 100s = 50s
    expect(c.lastSeek?.inSeconds, 50);
  });

  testWidgets('pointerCancel → 不 seek，恢复 play (如之前 playing)，onScrubEnd',
      (tester) async {
    final c = FakeNiumaPlayerController();
    c.value = c.value.copyWith(
      duration: const Duration(seconds: 100),
      phase: PlayerPhase.playing,
    );

    var endCalls = 0;
    await tester.pumpWidget(wrap(
      Align(
        alignment: Alignment.bottomCenter,
        child: NiumaShortVideoProgressBar(
          controller: c,
          theme: NiumaShortVideoTheme.defaults(),
          onScrubStart: () {},
          onScrubUpdate: (_) {},
          onScrubEnd: () => endCalls++,
        ),
      ),
    ));

    final barLeft =
        tester.getTopLeft(find.byType(NiumaShortVideoProgressBar));
    final gesture = await tester.startGesture(
      Offset(barLeft.dx + 100, barLeft.dy + 12),
    );
    await gesture.cancel();
    await tester.pump();

    expect(endCalls, 1); // onScrubEnd 仍调
    expect(c.lastSeek, isNull); // 但不 seek
    expect(c.playCount, greaterThan(0)); // 恢复 play
  });
}
