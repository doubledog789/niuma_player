import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/presentation/niuma_player.dart' as np_internal;
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

  group('didUpdateWidget controller / orchestrator swap', () {
    testWidgets('controller swap 时 listener 重 attach 到新 controller',
        (tester) async {
      final ctlA = FakeNiumaPlayerController();
      final ctlB = FakeNiumaPlayerController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NiumaPlayer(controller: ctlA)),
      ));

      // 推 ctlA 到 paused（强制控件显示）——基线。
      ctlA.value = _pausedValue();
      await tester.pump();
      expect(
        tester
            .widget<AnimatedOpacity>(find.descendant(
              of: find.byType(NiumaPlayer),
              matching: find.byType(AnimatedOpacity),
            ))
            .opacity,
        1.0,
      );

      // 换成 ctlB，并把 ctlB 推到 playing；同时 ctlA 推到 paused 应被忽略。
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NiumaPlayer(controller: ctlB)),
      ));
      ctlB.value = _playingValue();
      await tester.pump();
      // 新 controller 推 playing → 计时器开始，但 5s 内仍可见。
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<AnimatedOpacity>(find.descendant(
              of: find.byType(NiumaPlayer),
              matching: find.byType(AnimatedOpacity),
            ))
            .opacity,
        1.0,
      );

      // ctlA 这时即使推 paused 也不应影响（旧 listener 已 detach）——
      // 这里的间接断言是：5s 后 ctlB 的 playing 状态确实驱动了 hide。
      await tester.pump(const Duration(seconds: 5));
      expect(
        tester
            .widget<AnimatedOpacity>(find.descendant(
              of: find.byType(NiumaPlayer),
              matching: find.byType(AnimatedOpacity),
            ))
            .opacity,
        0.0,
        reason: '新 controller 的 playing 状态应当驱动 auto-hide',
      );
    });

    testWidgets('adSchedule null → non-null 时挂 NiumaAdOverlay', (tester) async {
      final ctl = FakeNiumaPlayerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NiumaPlayer(controller: ctl)),
      ));
      expect(find.byType(NiumaAdOverlay), findsNothing);

      const schedule = NiumaAdSchedule();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NiumaPlayer(
            controller: ctl,
            adSchedule: schedule,
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(NiumaAdOverlay), findsOneWidget,
          reason: 'didUpdateWidget 应识别新的 schedule 并构建 orchestrator');
    });
  });

  group('M9 review 修复', () {
    testWidgets('ad cue 活跃时 tap 视频区不切换 controls 可见状态',
        (tester) async {
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

      // 初始 opacity=1（控件可见）。
      AnimatedOpacity readOpacity() => tester.widget<AnimatedOpacity>(
            find.descendant(
              of: find.byType(NiumaPlayer),
              matching: find.byType(AnimatedOpacity),
            ),
          );
      expect(readOpacity().opacity, 1.0);

      // 找到 NiumaAdOverlay 的 orchestrator 并 fire 一个 cue。
      final overlay =
          tester.widget<NiumaAdOverlay>(find.byType(NiumaAdOverlay));
      overlay.orchestrator.activeCue.value = const AdCue(
        builder: _adBuilder,
        minDisplayDuration: Duration.zero,
      );
      overlay.orchestrator.activeCueType.value = AdCueType.preRoll;
      await tester.pump();
      // cue 进入隐藏控件——opacity → 0。
      expect(readOpacity().opacity, 0.0);

      // cue 活跃时 tap 视频区——应被忽略，控件仍隐藏。
      await tester.tapAt(tester.getCenter(find.byType(NiumaPlayer)));
      await tester.pump();
      expect(readOpacity().opacity, 0.0,
          reason: 'cue 活跃时 tap 不应切换控件可见');

      // dismissActive → controls 恢复。
      overlay.orchestrator.dismissActive();
      await tester.pump();
      expect(readOpacity().opacity, 1.0,
          reason: 'cue 离开后控件应恢复显示');
    });

    testWidgets(
        'NiumaFullscreenPage.route 透传 adSchedule——全屏页内含 NiumaAdOverlay',
        (tester) async {
      final ctl = FakeNiumaPlayerController();
      const schedule = NiumaAdSchedule();
      final emitter = FakeAnalyticsEmitter();
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox()),
      ));

      navKey.currentState!.push<void>(NiumaFullscreenPage.route(
        controller: ctl,
        adSchedule: schedule,
        adAnalyticsEmitter: emitter.call,
      ));
      await tester.pumpAndSettle();

      // 全屏页 NiumaPlayer 应继承 adSchedule，因此挂了 NiumaAdOverlay。
      expect(find.byType(NiumaAdOverlay), findsOneWidget,
          reason: 'NiumaFullscreenPage.route 应透传 adSchedule');

      // 关闭页面恢复。
      navKey.currentState!.pop();
      await tester.pumpAndSettle();
    });
  });

  group('M9 round-2 review 修复', () {
    testWidgets(
        'NiumaPlayerThemeData inherited 注入主题——FullscreenButton push 时透传到全屏页',
        (tester) async {
      // README 推荐写法：上层用 NiumaPlayerThemeData(child: NiumaPlayer(...))，
      // NiumaPlayer.theme 字段为 null。点击 fullscreen 进入全屏后，全屏页内
      // 的 widget 应当读到外层 inherited theme（而不是默认 theme）。
      final ctl = FakeNiumaPlayerController();
      const customTheme =
          NiumaPlayerTheme(accentColor: Color(0xFFAA0000), iconSize: 42);

      await tester.pumpWidget(MaterialApp(
        home: NiumaPlayerThemeData(
          data: customTheme,
          child: Scaffold(body: NiumaPlayer(controller: ctl)),
        ),
      ));

      // 点击外层的 FullscreenButton——它在 NiumaControlBar 里。
      await tester.tap(find.byType(FullscreenButton));
      await tester.pumpAndSettle();

      // 全屏页内的子树读到的 theme 应该是 customTheme（不是默认）。
      // 通过在全屏页内找 NiumaPlayerTheme.of 的间接证据：iconSize 应该是 42。
      final fullscreenIcons =
          tester.widgetList<IconButton>(find.descendant(
        of: find.byType(NiumaFullscreenPage),
        matching: find.byType(IconButton),
      ));
      expect(fullscreenIcons, isNotEmpty,
          reason: '全屏页内应有 IconButton');
      // 至少有一个 IconButton 用了 customTheme.iconSize=42。
      expect(
        fullscreenIcons.any((b) => b.iconSize == 42),
        isTrue,
        reason: '全屏页内的 IconButton 应当读到外层 NiumaPlayerThemeData '
            '注入的 customTheme（iconSize=42）',
      );
    });

    testWidgets(
        '_setControlsVisible 在 build 阶段触发时把 setState 延后到 post-frame',
        (tester) async {
      // R2-Important-4：之前的"cue 活跃时 tap 视频区不切换 controls"测试
      // 触发 _setControlsVisible 都是在 idle phase 走 sync setState 路径，
      // 没真覆盖到 post-frame 分支。这里通过 debugSchedulerPhaseOverride
      // 模拟 schedulerPhase=persistentCallbacks，让 _setControlsVisible
      // 真走 post-frame 入队分支，并断言 _pendingVisibleIntent 设置 +
      // 后续 frame fire 后落地。
      final ctl = FakeNiumaPlayerController();
      final key = GlobalKey<np_internal.NiumaPlayerStateForTesting>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NiumaPlayer(key: key, controller: ctl)),
      ));

      // 拿到内部 state——通过 @visibleForTesting accessors 调内部方法。
      final state = key.currentState!;
      expect(state.debugControlsVisible, isTrue);

      // 模拟"现在在 build 阶段"——_setControlsVisible 应当 enqueue 到
      // post-frame，而不是立刻 setState（否则会撞 framework lock）。
      np_internal.debugSchedulerPhaseOverride =
          SchedulerPhase.persistentCallbacks;
      try {
        state.debugSetControlsVisible(false);
        // post-frame 还没 fire——controls 仍是 visible，但 pendingIntent
        // 已经记录。
        expect(state.debugControlsVisible, isTrue,
            reason: 'persistentCallbacks 阶段不应同步 setState');
        expect(state.debugPendingVisibleIntent, isFalse,
            reason: '_pendingVisibleIntent 应记录最新意图（false）');

        // 再来一次反向：意图应当被覆盖成 true，仍未 fire。
        state.debugSetControlsVisible(true);
        // 注意：visible==current 时 _setControlsVisible 早 return 不入队，
        // 但是 _pendingVisibleIntent 还在；当 post-frame fire 时按 intent
        // 走，最终 _controlsVisible 不变（true→true）。
        expect(state.debugControlsVisible, isTrue);
      } finally {
        np_internal.debugSchedulerPhaseOverride = null;
      }

      // pump 一次让 post-frame callback fire——调用应当按最新 intent 落地。
      await tester.pump();
      // _pendingVisibleIntent 在 callback 里被清空。
      expect(state.debugPendingVisibleIntent, isNull,
          reason: 'post-frame 应当清空 pending intent');
      // 上面 pendingIntent=false（第二次同 visible 不变更 intent），post-frame
      // fire 后 _controlsVisible 应该真的变 false。
      expect(state.debugControlsVisible, isFalse,
          reason: 'post-frame 应按最新 pendingIntent 落地——visible=false');
    });

    testWidgets(
        'didUpdateWidget controlsAutoHideAfter 改变时重置计时器使用新值',
        (tester) async {
      final ctl = FakeNiumaPlayerController();

      Widget build(Duration autoHide) => MaterialApp(
            home: Scaffold(
              body: NiumaPlayer(
                controller: ctl,
                controlsAutoHideAfter: autoHide,
              ),
            ),
          );

      await tester.pumpWidget(build(const Duration(seconds: 10)));

      // 进入 playing：旧 10s 计时器启动。
      ctl.value = _playingValue();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      AnimatedOpacity readOpacity() => tester.widget<AnimatedOpacity>(
            find.descendant(
              of: find.byType(NiumaPlayer),
              matching: find.byType(AnimatedOpacity),
            ),
          );
      expect(readOpacity().opacity, 1.0, reason: '1s 时仍可见');

      // 改 controlsAutoHideAfter 到 2s——didUpdateWidget 应当 cancel 旧
      // 计时器并按新值重启。
      await tester.pumpWidget(build(const Duration(seconds: 2)));
      await tester.pump();

      // 改 props 那一刻起再过 2s 应该隐藏（如果 didUpdateWidget 没处理，
      // 旧 10s 计时器仍在跑，到这里只过了 1+2=3s，远不到 10s，控件仍可见）。
      await tester.pump(const Duration(seconds: 2, milliseconds: 100));
      expect(readOpacity().opacity, 0.0,
          reason: 'controlsAutoHideAfter 改成 2s 后应当按新值重启计时器');
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

  group('NiumaPlayer + danmakuController 集成', () {
    testWidgets('传 danmakuController 时子树注入 NiumaDanmakuScope',
        (tester) async {
      final video = FakeNiumaPlayerController();
      final danmaku = NiumaDanmakuController()
        ..add(const DanmakuItem(position: Duration(seconds: 1), text: 'hi'));

      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 360,
          height: 200,
          child: NiumaPlayer(
            controller: video,
            danmakuController: danmaku,
          ),
        ),
      ));
      await tester.pump();
      // ControlBar 内的 DanmakuButton 应能找到 scope 注入的 controller
      final button = find.byType(DanmakuButton);
      expect(button, findsOneWidget);
      expect(danmaku.settings.visible, isTrue);
      // tap 改 visible
      await tester.tap(button);
      await tester.pump();
      expect(danmaku.settings.visible, isFalse);
      danmaku.dispose();
    });

    testWidgets('不传 danmakuController 时 DanmakuButton 是禁用态',
        (tester) async {
      final video = FakeNiumaPlayerController();
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 360,
          height: 200,
          child: NiumaPlayer(controller: video),
        ),
      ));
      final ip = find.descendant(
        of: find.byType(DanmakuButton),
        matching: find.byWidgetPredicate(
          (w) => w is IgnorePointer && w.ignoring == true,
        ),
      );
      expect(ip, findsOneWidget);
    });

    testWidgets('NiumaPlayer 传 danmakuController → ConfigScope.danmakuController 同步',
        (tester) async {
      final video = FakeNiumaPlayerController();
      final danmaku = NiumaDanmakuController();
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 360,
          height: 200,
          child: NiumaPlayer(
            controller: video,
            danmakuController: danmaku,
          ),
        ),
      ));
      await tester.pump();
      // ConfigScope 包在 NiumaPlayer 的 build 里——断言子树里有 ConfigScope
      // 且它的 danmakuController 是同一实例。
      final scopeFound = tester.widget<np_internal.NiumaPlayerConfigScope>(
          find.byType(np_internal.NiumaPlayerConfigScope));
      expect(scopeFound.danmakuController, same(danmaku));
      danmaku.dispose();
    });
  });
}

Widget _adBuilder(BuildContext _, AdController __) =>
    const SizedBox(width: 100, height: 100, child: Text('AD'));
