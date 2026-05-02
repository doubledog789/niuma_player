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
    testWidgets('isActive=true 初始化时调 controller.play', (tester) async {
      final c = FakeNiumaPlayerController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c, isActive: true),
        ),
      ));
      await tester.pump();

      // initState（postFrame）应触发 play——首屏自动播
      expect(c.playCount, greaterThanOrEqualTo(1));
    });

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

  group('loop=true 循环', () {
    testWidgets('phase=ended → seekTo(0) + play', (tester) async {
      final c = FakeNiumaPlayerController();
      c.value = c.value.copyWith(
        duration: const Duration(seconds: 30),
        position: const Duration(seconds: 30),
        phase: PlayerPhase.playing,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c),  // loop=true 默认
        ),
      ));

      // 模拟视频结束
      c.value = c.value.copyWith(phase: PlayerPhase.ended);
      await tester.pump();

      expect(c.lastSeek, Duration.zero);
      expect(c.playCount, greaterThan(0));
    });

    testWidgets('loop=false → 不自动循环', (tester) async {
      final c = FakeNiumaPlayerController();
      c.value = c.value.copyWith(
        duration: const Duration(seconds: 30),
        position: const Duration(seconds: 30),
        phase: PlayerPhase.playing,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c, loop: false),
        ),
      ));
      final playBeforeEnd = c.playCount;

      c.value = c.value.copyWith(phase: PlayerPhase.ended);
      await tester.pump();

      // 没自动循环：seekTo(0) 不应被调，play() 也不应被再次调
      expect(c.lastSeek, isNull);
      expect(c.playCount, playBeforeEnd);
    });
  });

  group('muted + fit', () {
    testWidgets('muted=true → initState 调 setVolume(0)', (tester) async {
      final c = FakeNiumaPlayerController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c, muted: true),
        ),
      ));
      await tester.pump();

      expect(c.lastVolume, 0.0);
    });

    testWidgets('muted=false → 不调 setVolume', (tester) async {
      final c = FakeNiumaPlayerController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c, muted: false),
        ),
      ));
      await tester.pump();

      expect(c.lastVolume, isNull);
    });

    testWidgets('fit prop 透传到 FittedBox', (tester) async {
      final c = FakeNiumaPlayerController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c, fit: BoxFit.contain),
        ),
      ));

      final box = tester.widget<FittedBox>(
        find.descendant(
          of: find.byType(NiumaShortVideoPlayer),
          matching: find.byType(FittedBox),
        ),
      );
      expect(box.fit, BoxFit.contain);
    });
  });

  group('单击 toggle + 长按 2x', () {
    testWidgets('单击 phase=playing → pause', (tester) async {
      final c = FakeNiumaPlayerController();
      c.value = c.value.copyWith(phase: PlayerPhase.playing);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: NiumaShortVideoPlayer(controller: c),
          ),
        ),
      ));

      await tester.tap(find.byType(NiumaShortVideoPlayer));
      await tester.pump();
      expect(c.pauseCount, 1);
    });

    testWidgets('单击 phase=paused → play', (tester) async {
      final c = FakeNiumaPlayerController();
      c.value = c.value.copyWith(phase: PlayerPhase.paused);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: NiumaShortVideoPlayer(controller: c),
          ),
        ),
      ));
      final beforeTap = c.playCount;

      await tester.tap(find.byType(NiumaShortVideoPlayer));
      await tester.pump();
      expect(c.playCount, greaterThan(beforeTap));
    });

    testWidgets('onSingleTap != null → 调 callback 且不调 controller play/pause',
        (tester) async {
      final c = FakeNiumaPlayerController();
      c.value = c.value.copyWith(phase: PlayerPhase.playing);

      var callbackCalls = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: NiumaShortVideoPlayer(
              controller: c,
              onSingleTap: (_) => callbackCalls++,
            ),
          ),
        ),
      ));
      final pauseBefore = c.pauseCount;
      final playBefore = c.playCount;

      await tester.tap(find.byType(NiumaShortVideoPlayer));
      await tester.pump();
      expect(callbackCalls, 1);
      expect(c.pauseCount, pauseBefore);   // 没调 pause
      expect(c.playCount, playBefore);     // 没调 play
    });

    testWidgets('长按 → setSpeed(2.0)，松手恢复原速', (tester) async {
      final c = FakeNiumaPlayerController();
      c.value = c.value.copyWith(playbackSpeed: 1.0);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: NiumaShortVideoPlayer(controller: c),
          ),
        ),
      ));

      final center = tester.getCenter(find.byType(NiumaShortVideoPlayer));
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 600));
      expect(c.lastSpeed, 2.0);

      await gesture.up();
      await tester.pump();
      expect(c.lastSpeed, 1.0);
    });
  });

  group('overlayBuilder + scrub flow', () {
    testWidgets('overlayBuilder=null → 不挂', (tester) async {
      final c = FakeNiumaPlayerController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c),
        ),
      ));

      expect(find.byKey(const ValueKey('test-overlay')), findsNothing);
    });

    testWidgets('overlayBuilder != null → 挂到树上', (tester) async {
      final c = FakeNiumaPlayerController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(
            controller: c,
            overlayBuilder: (ctx, value) =>
                const SizedBox.expand(child: ColoredBox(
                    color: Color(0x80FF0000),
                    child: SizedBox.expand(
                        key: ValueKey('test-overlay')))),
          ),
        ),
      ));

      expect(find.byKey(const ValueKey('test-overlay')), findsOneWidget);
    });

    testWidgets('拖动开始时 controller.pause + 显示 scrubLabel', (tester) async {
      final c = FakeNiumaPlayerController();
      c.value = c.value.copyWith(
        duration: const Duration(seconds: 100),
        phase: PlayerPhase.playing,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: NiumaShortVideoPlayer(controller: c),
          ),
        ),
      ));

      // 找到 progressBar 并拖动
      final barCenter =
          tester.getCenter(find.byType(NiumaShortVideoProgressBar));
      final gesture = await tester.startGesture(barCenter);
      addTearDown(() async => gesture.up());
      await tester.pump();

      expect(c.pauseCount, greaterThan(0));
      expect(find.byType(NiumaShortVideoScrubLabel), findsOneWidget);
    });

    testWidgets('松手时 seekTo + 恢复 play（如之前 playing）', (tester) async {
      final c = FakeNiumaPlayerController();
      c.value = c.value.copyWith(
        duration: const Duration(seconds: 100),
        phase: PlayerPhase.playing,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: NiumaShortVideoPlayer(controller: c),
          ),
        ),
      ));

      final barLeft =
          tester.getTopLeft(find.byType(NiumaShortVideoProgressBar));
      final gesture = await tester.startGesture(
        Offset(barLeft.dx + 100, barLeft.dy + 12),
      );
      await gesture.moveTo(Offset(barLeft.dx + 200, barLeft.dy + 12));
      final playBeforeUp = c.playCount;
      await gesture.up();
      await tester.pump();

      expect(c.lastSeek?.inSeconds, 50);
      expect(c.playCount, greaterThan(playBeforeUp));
      expect(find.byType(NiumaShortVideoScrubLabel), findsNothing);
    });

    testWidgets('松手时若之前 paused → 不恢复 play', (tester) async {
      final c = FakeNiumaPlayerController();
      c.value = c.value.copyWith(
        duration: const Duration(seconds: 100),
        phase: PlayerPhase.paused,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: NiumaShortVideoPlayer(controller: c),
          ),
        ),
      ));

      final barLeft =
          tester.getTopLeft(find.byType(NiumaShortVideoProgressBar));
      final gesture = await tester.startGesture(
        Offset(barLeft.dx + 100, barLeft.dy + 12),
      );
      final playBeforeUp = c.playCount;
      await gesture.up();
      await tester.pump();

      expect(c.playCount, playBeforeUp);   // 未恢复 play
    });
  });

  group('danmakuController 集成', () {
    testWidgets('null → 不挂 NiumaDanmakuOverlay', (tester) async {
      final c = FakeNiumaPlayerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c),
        ),
      ));
      expect(find.byType(NiumaDanmakuOverlay), findsNothing);
    });

    testWidgets('非 null → 挂 NiumaDanmakuOverlay', (tester) async {
      final c = FakeNiumaPlayerController();
      final dc = NiumaDanmakuController();
      addTearDown(dc.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(
            controller: c,
            danmakuController: dc,
          ),
        ),
      ));
      expect(find.byType(NiumaDanmakuOverlay), findsOneWidget);
    });

    testWidgets('非 null → 注入 NiumaDanmakuScope', (tester) async {
      final c = FakeNiumaPlayerController();
      final dc = NiumaDanmakuController();
      addTearDown(dc.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(
            controller: c,
            danmakuController: dc,
          ),
        ),
      ));
      expect(find.byType(NiumaDanmakuScope), findsOneWidget);
    });

    testWidgets('弹幕 IgnorePointer 包裹（让 tap 透传）', (tester) async {
      final c = FakeNiumaPlayerController();
      final dc = NiumaDanmakuController();
      addTearDown(dc.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(
            controller: c,
            danmakuController: dc,
          ),
        ),
      ));
      final ignore = find.ancestor(
        of: find.byType(NiumaDanmakuOverlay),
        matching: find.byType(IgnorePointer),
      );
      expect(ignore, findsAtLeastNWidgets(1));
    });
  });

  group('leftCenterBuilder slot', () {
    testWidgets('null → 不挂', (tester) async {
      final c = FakeNiumaPlayerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaShortVideoPlayer(controller: c),
        ),
      ));
      expect(find.byKey(const ValueKey('left-center-test')), findsNothing);
    });

    testWidgets('非 null → 挂在树上、左侧、垂直居中', (tester) async {
      final c = FakeNiumaPlayerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: NiumaShortVideoPlayer(
              controller: c,
              leftCenterBuilder: (ctx, c) => const SizedBox(
                key: ValueKey('left-center-test'),
                width: 36,
                height: 36,
              ),
            ),
          ),
        ),
      ));

      expect(find.byKey(const ValueKey('left-center-test')), findsOneWidget);
      final pos = tester.getCenter(find.byKey(const ValueKey('left-center-test')));
      // 垂直居中（容器 600 中心 = 300）
      expect(pos.dy, 300);
      // 左侧（小于宽度的一半）
      expect(pos.dx, lessThan(200));
    });
  });
}
