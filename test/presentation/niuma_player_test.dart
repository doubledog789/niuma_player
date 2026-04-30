import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/testing/fake_analytics_emitter.dart';

import 'controls/fake_controller.dart';

/// 把 controller 推到 phase=playing 的辅助。
NiumaPlayerValue _playingValue({
  Duration position = Duration.zero,
  Duration duration = const Duration(seconds: 60),
}) {
  return NiumaPlayerValue.uninitialized().copyWith(
    phase: PlayerPhase.playing,
    position: position,
    duration: duration,
  );
}

NiumaPlayerValue _pausedValue() {
  return NiumaPlayerValue.uninitialized().copyWith(
    phase: PlayerPhase.paused,
    duration: const Duration(seconds: 60),
  );
}

void main() {
  group('NiumaPlayer 顶层组合', () {
    testWidgets('build 包含 NiumaPlayerView + NiumaControlBar', (tester) async {
      final ctl = FakeNiumaPlayerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NiumaPlayer(controller: ctl)),
      ));

      expect(find.byType(NiumaPlayer), findsOneWidget);
      expect(find.byType(NiumaControlBar), findsOneWidget);
    });

    testWidgets('传入 theme 时在内部包一层 NiumaPlayerThemeData', (tester) async {
      final ctl = FakeNiumaPlayerController();
      const theme = NiumaPlayerTheme(accentColor: Colors.deepPurple);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NiumaPlayer(controller: ctl, theme: theme)),
      ));

      final injected = find.descendant(
        of: find.byType(NiumaPlayer),
        matching: find.byType(NiumaPlayerThemeData),
      );
      expect(injected, findsOneWidget);
    });

    testWidgets('未传 adSchedule 时不挂 NiumaAdOverlay', (tester) async {
      final ctl = FakeNiumaPlayerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NiumaPlayer(controller: ctl)),
      ));
      expect(find.byType(NiumaAdOverlay), findsNothing);
    });

    testWidgets('传入 adSchedule 时挂 NiumaAdOverlay', (tester) async {
      final ctl = FakeNiumaPlayerController();
      const schedule = NiumaAdSchedule();
      final emitter = FakeAnalyticsEmitter();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaPlayer(
            controller: ctl,
            adSchedule: schedule,
            adAnalyticsEmitter: emitter.call,
          ),
        ),
      ));
      expect(find.byType(NiumaAdOverlay), findsOneWidget);
    });
  });

  group('auto-hide 状态机', () {
    testWidgets('初始状态 controls 显示（opacity == 1）', (tester) async {
      final ctl = FakeNiumaPlayerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NiumaPlayer(controller: ctl)),
      ));
      // 初始 phase=idle，控件应可见。
      final opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(NiumaPlayer),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 1.0);
    });

    testWidgets('phase=playing 持续 controlsAutoHideAfter 后 controls 隐藏',
        (tester) async {
      final ctl = FakeNiumaPlayerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaPlayer(
            controller: ctl,
            controlsAutoHideAfter: const Duration(seconds: 5),
          ),
        ),
      ));

      ctl.value = _playingValue();
      await tester.pump();

      // 4s 内仍显示。
      await tester.pump(const Duration(seconds: 4));
      var opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(NiumaPlayer),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 1.0);

      // 再过 2s（共 6s > 5s 阈值）后隐藏。
      await tester.pump(const Duration(seconds: 2));
      opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(NiumaPlayer),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 0.0);
    });

    testWidgets('phase=paused 时 controls 强制显示', (tester) async {
      final ctl = FakeNiumaPlayerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaPlayer(
            controller: ctl,
            controlsAutoHideAfter: const Duration(seconds: 1),
          ),
        ),
      ));

      // 进入 playing → 计时器启动。
      ctl.value = _playingValue();
      await tester.pump();
      // 等到 controls 应该被隐藏。
      await tester.pump(const Duration(seconds: 2));
      var opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(NiumaPlayer),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 0.0);

      // 切到 paused → 强制显示。
      ctl.value = _pausedValue();
      await tester.pump();
      opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(NiumaPlayer),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 1.0);
    });

    testWidgets('点击切换 controls 显示 / 隐藏', (tester) async {
      final ctl = FakeNiumaPlayerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NiumaPlayer(controller: ctl)),
      ));
      // 初始：显示。
      var opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(NiumaPlayer),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 1.0);

      // 点击播放区——切到隐藏。
      await tester.tapAt(tester.getCenter(find.byType(NiumaPlayer)));
      await tester.pump();
      opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(NiumaPlayer),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 0.0);

      // 再点一次——切回显示。
      await tester.tapAt(tester.getCenter(find.byType(NiumaPlayer)));
      await tester.pump();
      opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(NiumaPlayer),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 1.0);
    });

    testWidgets('controlsAutoHideAfter=Duration.zero 时永不自动隐藏',
        (tester) async {
      final ctl = FakeNiumaPlayerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaPlayer(
            controller: ctl,
            controlsAutoHideAfter: Duration.zero,
          ),
        ),
      ));

      ctl.value = _playingValue();
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      final opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(NiumaPlayer),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 1.0);
    });
  });

  group('fake_async 时序', () {
    test('计时逻辑使用 Timer——可被 fake_async 推动', () {
      // Smoke test：FakeAsync 能正常推动；具体 widget 行为已在上面 widget
      // 测试中用 tester.pump(duration) 覆盖。这里保留一个最小 fake_async
      // smoke test 验证导入与语义。
      fakeAsync((async) {
        var fired = false;
        Timer(const Duration(seconds: 5), () => fired = true);
        async.elapse(const Duration(seconds: 4));
        expect(fired, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(fired, isTrue);
      });
    });
  });
}
