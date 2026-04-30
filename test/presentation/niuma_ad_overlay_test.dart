import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/testing/fake_analytics_emitter.dart';

import 'controls/fake_controller.dart';

class _FakePlayerValue extends ChangeNotifier
    implements ValueListenable<NiumaPlayerValue> {
  NiumaPlayerValue _v = NiumaPlayerValue.uninitialized();

  @override
  NiumaPlayerValue get value => _v;

  void emit(NiumaPlayerValue v) {
    _v = v;
    notifyListeners();
  }
}

/// 构造一个手动驱动的 orchestrator——不通过 player.emit 走真实路径，
/// 而是直接 set activeCue / activeCueType，让测试关注 overlay 本身。
AdSchedulerOrchestrator _orch({
  AdCue? preRoll,
  FakeAnalyticsEmitter? emitter,
}) {
  final player = _FakePlayerValue();
  return AdSchedulerOrchestrator(
    schedule: NiumaAdSchedule(preRoll: preRoll),
    playerValue: player,
    onPlay: () {},
    onPause: () {},
    analytics: emitter?.call,
  );
}

void main() {
  testWidgets('cue == null 时返回 SizedBox.shrink', (tester) async {
    final orch = _orch();
    final ctl = FakeNiumaPlayerController();
    final fake = FakeAnalyticsEmitter();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orch,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));

    expect(find.byType(NiumaAdOverlay), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
    // 没有 cue 时，不应该有任何"广告内容"的标记。
    expect(find.text('AD'), findsNothing);
    orch.dispose();
  });

  testWidgets('cue 出现时调 videoController.pause（pauseVideoWhileShowing=true）',
      (tester) async {
    final orch = _orch();
    final ctl = FakeNiumaPlayerController();
    ctl.value = NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.playing);
    final fake = FakeAnalyticsEmitter();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orch,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));

    expect(ctl.pauseCount, 0);

    orch.activeCue.value = const AdCue(
      builder: _adBuilder,
    );
    orch.activeCueType.value = AdCueType.preRoll;
    await tester.pump();

    expect(ctl.pauseCount, 1);
    orch.dispose();
  });

  testWidgets('pauseVideoWhileShowing=false 时 cue 出现不调 pause',
      (tester) async {
    final orch = _orch();
    final ctl = FakeNiumaPlayerController();
    final fake = FakeAnalyticsEmitter();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orch,
          videoController: ctl,
          emitter: fake.call,
          pauseVideoWhileShowing: false,
        ),
      ),
    ));

    orch.activeCue.value = const AdCue(builder: _adBuilder);
    orch.activeCueType.value = AdCueType.preRoll;
    await tester.pump();

    expect(ctl.pauseCount, 0);
    orch.dispose();
  });

  testWidgets('cue.dismissOnTap=true 整覆盖区可 tap 触发 dismiss', (tester) async {
    final orch = _orch();
    final ctl = FakeNiumaPlayerController();
    final fake = FakeAnalyticsEmitter();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: NiumaAdOverlay(
            orchestrator: orch,
            videoController: ctl,
            emitter: fake.call,
          ),
        ),
      ),
    ));

    // 用 minDisplayDuration=0 让 dismiss 立即生效。
    orch.activeCue.value = const AdCue(
      builder: _adBuilder,
      minDisplayDuration: Duration.zero,
      dismissOnTap: true,
    );
    orch.activeCueType.value = AdCueType.preRoll;
    await tester.pump();

    // 整覆盖区的 GestureDetector 在 widget tree 中存在；点击它。
    await tester.tapAt(const Offset(50, 50));
    await tester.pump();

    // dismiss 走正常路径会发 AdDismissed + 调 dismissActive → activeCue 清空。
    expect(orch.activeCue.value, isNull);
    expect(
      fake.events.whereType<AdDismissed>().toList(),
      hasLength(1),
    );
    orch.dispose();
  });

  testWidgets('cue.timeout 触发后自动 dismiss + emit AdDismissed(timeout)',
      (tester) async {
    final orch = _orch();
    final ctl = FakeNiumaPlayerController();
    final fake = FakeAnalyticsEmitter();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orch,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));

    orch.activeCue.value = const AdCue(
      builder: _adBuilder,
      minDisplayDuration: Duration.zero,
      timeout: Duration(milliseconds: 100),
    );
    orch.activeCueType.value = AdCueType.preRoll;
    await tester.pump();

    expect(orch.activeCue.value, isNotNull);

    // 超过 timeout，timer 应该 fire。
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    expect(orch.activeCue.value, isNull);
    final dismissed = fake.events.whereType<AdDismissed>().toList();
    expect(dismissed, hasLength(1));
    expect(dismissed.first.reason, AdDismissReason.timeout);
    orch.dispose();
  });

  testWidgets('cue 结束后视频原本在播则恢复 play', (tester) async {
    final orch = _orch();
    final ctl = FakeNiumaPlayerController();
    ctl.value = NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.playing);
    final fake = FakeAnalyticsEmitter();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orch,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));

    orch.activeCue.value = const AdCue(builder: _adBuilder);
    orch.activeCueType.value = AdCueType.preRoll;
    await tester.pump();

    expect(ctl.pauseCount, 1);
    expect(ctl.playCount, 0);

    // cue 走完——orchestrator 清掉 activeCue（模拟外部 dismiss）。
    orch.dismissActive();
    await tester.pump();

    expect(ctl.playCount, 1);
    orch.dispose();
  });

  testWidgets('cue.builder 调 reportImpression → emit AdImpression', (tester) async {
    final orch = _orch();
    final ctl = FakeNiumaPlayerController();
    final fake = FakeAnalyticsEmitter();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orch,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));

    orch.activeCue.value = AdCue(
      minDisplayDuration: Duration.zero,
      builder: (ctx, ctrl) {
        // 测试钩子：mount 完调 reportImpression。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ctrl.reportImpression();
        });
        return const Text('AD');
      },
    );
    orch.activeCueType.value = AdCueType.preRoll;
    await tester.pump();
    await tester.pump();

    expect(
      fake.events.whereType<AdImpression>().toList(),
      hasLength(1),
    );
    expect(
      fake.events.whereType<AdImpression>().first.cueType,
      AdCueType.preRoll,
    );
    orch.dispose();
  });

  testWidgets('cue.builder 调 reportClick → emit AdClick', (tester) async {
    final orch = _orch();
    final ctl = FakeNiumaPlayerController();
    final fake = FakeAnalyticsEmitter();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orch,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));

    orch.activeCue.value = AdCue(
      minDisplayDuration: Duration.zero,
      builder: (ctx, ctrl) {
        return GestureDetector(
          onTap: ctrl.reportClick,
          behavior: HitTestBehavior.opaque,
          child: const SizedBox(
            width: 100,
            height: 100,
            child: Text('AD'),
          ),
        );
      },
    );
    orch.activeCueType.value = AdCueType.preRoll;
    await tester.pump();

    await tester.tap(find.text('AD'));
    await tester.pump();

    final clicks = fake.events.whereType<AdClick>().toList();
    expect(clicks, hasLength(1));
    expect(clicks.first.cueType, AdCueType.preRoll);
    orch.dispose();
  });

  testWidgets('cue.builder 抛异常时 catch + emit AdDismissed 并 dismissActive',
      (tester) async {
    final orch = _orch();
    final ctl = FakeNiumaPlayerController();
    final fake = FakeAnalyticsEmitter();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orch,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));

    orch.activeCue.value = AdCue(
      minDisplayDuration: Duration.zero,
      builder: (ctx, ctrl) {
        throw StateError('builder boom');
      },
    );
    orch.activeCueType.value = AdCueType.preRoll;
    // 让 build 跑一遍并暴露异常。
    await tester.pump();
    await tester.pump();

    // 异常被 overlay 捕获 → activeCue 清空 + 上报 AdDismissed。
    expect(orch.activeCue.value, isNull);
    final dismissed = fake.events.whereType<AdDismissed>().toList();
    expect(dismissed, hasLength(1));
    orch.dispose();
  });

  testWidgets('cue.builder 抛异常时 reason=AdDismissReason.error', (tester) async {
    // M9 review 要求：builder 异常专用 error 而不是冒充 timeout。
    final orch = _orch();
    final ctl = FakeNiumaPlayerController();
    final fake = FakeAnalyticsEmitter();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orch,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));

    orch.activeCue.value = AdCue(
      minDisplayDuration: Duration.zero,
      builder: (ctx, ctrl) => throw StateError('builder boom'),
    );
    orch.activeCueType.value = AdCueType.preRoll;
    await tester.pump();
    await tester.pump();

    final dismissed = fake.events.whereType<AdDismissed>().toList();
    expect(dismissed, hasLength(1));
    expect(dismissed.first.reason, AdDismissReason.error,
        reason: '异常路径应使用 AdDismissReason.error，不再冒充 timeout');
    orch.dispose();
  });

  testWidgets('orchestrator swap 时 detach 旧 listener，attach 新 listener',
      (tester) async {
    final orchA = _orch();
    final orchB = _orch();
    final ctl = FakeNiumaPlayerController();
    final fake = FakeAnalyticsEmitter();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orchA,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));

    // 切换 orchestrator B。
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orchB,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));
    await tester.pump();

    // orchA 上 fire cue——overlay 不应当响应（已 detach）。
    orchA.activeCue.value = const AdCue(
      builder: _adBuilder,
      minDisplayDuration: Duration.zero,
    );
    orchA.activeCueType.value = AdCueType.preRoll;
    await tester.pump();
    expect(find.text('AD'), findsNothing,
        reason: '旧 orchestrator 的 cue 不应再驱动 overlay');

    // orchB 上 fire cue——overlay 应当响应。
    orchB.activeCue.value = const AdCue(
      builder: _adBuilder,
      minDisplayDuration: Duration.zero,
    );
    orchB.activeCueType.value = AdCueType.preRoll;
    await tester.pump();
    expect(find.text('AD'), findsOneWidget,
        reason: '新 orchestrator 的 cue 应当驱动 overlay');

    orchA.dispose();
    orchB.dispose();
  });

  testWidgets(
      'orchestrator swap during active cue 时恢复底层视频 play（pauseVideoWhileShowing=true）',
      (tester) async {
    // R2-Important-1：旧 orchestrator 持有 active cue + 底层视频原本在播
    // → swap 到新 orchestrator 时，旧 cue 的 pause 已经把视频停下，但
    // didUpdateWidget swap 分支只 dispose adCtrl + 重置 _wasPlayingBeforeCue
    // 而没 undo 那次 pause——结果视频留在 paused 状态。
    final orchA = _orch();
    final orchB = _orch();
    final ctl = FakeNiumaPlayerController();
    ctl.value = NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.playing);
    final fake = FakeAnalyticsEmitter();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orchA,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));

    // orchA 上 fire cue——cue 出现时 overlay 自动调 ctl.pause()。
    orchA.activeCue.value = const AdCue(
      builder: _adBuilder,
      minDisplayDuration: Duration.zero,
    );
    orchA.activeCueType.value = AdCueType.preRoll;
    await tester.pump();
    expect(ctl.pauseCount, 1,
        reason: 'cue 出现时 pauseVideoWhileShowing=true 应当调用 pause');
    expect(ctl.playCount, 0);

    // swap 到 orchB——此时旧 orchA 仍然持有 activeCue，旧 cue 的 pause 已
    // 经发生但还没恢复。didUpdateWidget 的 swap 分支应当先恢复
    // _wasPlayingBeforeCue 的 play，再做 detach / reset。
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orchB,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));
    await tester.pump();

    expect(ctl.playCount, 1,
        reason: 'orchestrator swap 时 active cue 之前在播——应当恢复 play');

    orchA.dispose();
    orchB.dispose();
  });

  testWidgets('overlay unmount during cue 调 _adCtrl.dispose 关闭 elapsedStream',
      (tester) async {
    final orch = _orch();
    final ctl = FakeNiumaPlayerController();
    final fake = FakeAnalyticsEmitter();

    // 用一个 builder 把内部 controller 暴露到外面，便于断言 elapsedStream 状态。
    AdController? capturedCtrl;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaAdOverlay(
          orchestrator: orch,
          videoController: ctl,
          emitter: fake.call,
        ),
      ),
    ));

    orch.activeCue.value = AdCue(
      minDisplayDuration: Duration.zero,
      builder: (ctx, ctrl) {
        capturedCtrl = ctrl;
        return const Text('AD');
      },
    );
    orch.activeCueType.value = AdCueType.preRoll;
    await tester.pump();

    expect(capturedCtrl, isNotNull);

    // 订阅 elapsedStream，unmount 后应当被 close（onDone 被调）。
    var streamDone = false;
    capturedCtrl!.elapsedStream.listen(
      (_) {},
      onDone: () => streamDone = true,
    );

    // unmount overlay——切换到一个完全不同的 widget 树。
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(streamDone, isTrue,
        reason: 'overlay unmount 时 _adCtrl.dispose 应关闭 elapsedStream');
    orch.dispose();
  });
}

/// 简单的 cue.builder——返回带文字的 SizedBox。
Widget _adBuilder(BuildContext _, AdController __) =>
    const SizedBox(width: 100, height: 100, child: Text('AD'));
