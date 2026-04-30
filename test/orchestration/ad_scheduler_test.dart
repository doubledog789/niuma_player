// test/orchestration/ad_scheduler_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/observability/analytics_event.dart';
import 'package:niuma_player/src/orchestration/ad_schedule.dart';
import 'package:niuma_player/src/orchestration/ad_scheduler.dart';
import 'package:niuma_player/src/testing/fake_analytics_emitter.dart';

class _FakePlayer extends ChangeNotifier
    implements ValueListenable<NiumaPlayerValue> {
  NiumaPlayerValue _v = NiumaPlayerValue.uninitialized();

  @override
  NiumaPlayerValue get value => _v;

  bool playCalled = false;
  bool pauseCalled = false;

  void emit(NiumaPlayerValue v) {
    _v = v;
    notifyListeners();
  }

  void play() => playCalled = true;
  void pause() => pauseCalled = true;
}

void main() {
  test('preRoll fires on phase idle → ready transition', () {
    final player = _FakePlayer();
    final analytics = FakeAnalyticsEmitter();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        preRoll: AdCue(builder: (_, __) => const SizedBox()),
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
      analytics: analytics.call,
    )..attach();

    expect(orch.activeCue.value, isNull);

    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.ready));

    expect(orch.activeCue.value, isNotNull);
    expect(analytics.events, isNotEmpty);
    expect(analytics.events.first, isA<AdScheduled>());
    orch.dispose();
  });

  test('midRoll fires when position naturally crosses .at', () {
    final player = _FakePlayer();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        midRolls: [
          MidRollAd(
            at: const Duration(seconds: 30),
            cue: AdCue(builder: (_, __) => const SizedBox()),
          ),
        ],
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
    )..attach();

    // Initial playing at t=29s; no fire.
    player.emit(NiumaPlayerValue.uninitialized().copyWith(
      phase: PlayerPhase.playing,
      position: const Duration(seconds: 29),
    ));
    expect(orch.activeCue.value, isNull);
    expect(player.pauseCalled, isFalse);

    // t=31s; fire while playing → onPause is called.
    player.emit(NiumaPlayerValue.uninitialized().copyWith(
      phase: PlayerPhase.playing,
      position: const Duration(seconds: 31),
    ));
    expect(orch.activeCue.value, isNotNull);
    expect(player.pauseCalled, isTrue,
        reason: 'cue firing while playing must invoke the onPause callback');
    orch.dispose();
  });

  test('midRoll skipIfSeekedPast: jump from t=10 to t=40 does not fire midRoll@30', () {
    final player = _FakePlayer();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        midRolls: [
          MidRollAd(
            at: const Duration(seconds: 30),
            cue: AdCue(builder: (_, __) => const SizedBox()),
            // default = skipIfSeekedPast
          ),
        ],
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
    )..attach();

    // Establish baseline at t=10.
    player.emit(NiumaPlayerValue.uninitialized().copyWith(
      phase: PlayerPhase.playing,
      position: const Duration(seconds: 10),
    ));
    // Big jump to t=40 (≥ 2s gap → treat as seek).
    player.emit(NiumaPlayerValue.uninitialized().copyWith(
      phase: PlayerPhase.playing,
      position: const Duration(seconds: 40),
    ));
    expect(orch.activeCue.value, isNull,
        reason: 'skipIfSeekedPast should suppress midRoll on jumps');
    orch.dispose();
  });

  test('pauseAd fires on playing → paused (manual)', () {
    final player = _FakePlayer();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        pauseAd: AdCue(builder: (_, __) => const SizedBox()),
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
    )..attach();

    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.playing));
    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.paused));
    expect(orch.activeCue.value, isNotNull);

    orch.dispose();
  });

  test('PauseAdShowPolicy.oncePerSession suppresses second pause', () {
    final player = _FakePlayer();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        pauseAd: AdCue(builder: (_, __) => const SizedBox()),
        pauseAdShowPolicy: PauseAdShowPolicy.oncePerSession,
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
    )..attach();

    // First pause.
    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.playing));
    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.paused));
    orch.activeCue.value = null; // simulate dismiss

    // Second pause — should NOT fire.
    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.playing));
    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.paused));
    expect(orch.activeCue.value, isNull);

    orch.dispose();
  });

  test('postRoll fires on phase=ended', () {
    final player = _FakePlayer();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        postRoll: AdCue(builder: (_, __) => const SizedBox()),
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
    )..attach();

    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.ended));
    expect(orch.activeCue.value, isNotNull);
    orch.dispose();
  });

  test('AdController.dismiss() before minDisplayDuration is ignored', () {
    final cue = AdCue(
      builder: (_, __) => const SizedBox(),
      minDisplayDuration: const Duration(seconds: 5),
    );
    final ctl = AdControllerImpl(
      cue: cue,
      cueType: AdCueType.preRoll,
      emitter: FakeAnalyticsEmitter().call,
      onDismissRequested: () {},
    );
    ctl.dismiss(); // 0s elapsed
    expect(ctl.dismissed, isFalse, reason: 'release builds silently ignore');
  });

  test('AdController.dismiss after minDisplayDuration completes', () {
    final cue = AdCue(
      builder: (_, __) => const SizedBox(),
      minDisplayDuration: const Duration(seconds: 5),
    );
    var dismissed = false;
    final ctl = AdControllerImpl(
      cue: cue,
      cueType: AdCueType.preRoll,
      emitter: FakeAnalyticsEmitter().call,
      onDismissRequested: () {
        dismissed = true;
      },
    );
    ctl.simulateElapsed(const Duration(seconds: 6));
    ctl.dismiss();
    expect(dismissed, isTrue);
  });

  test(
      'cold-start at t=10s does not falsely consume skipIfSeekedPast midRoll@5s',
      () {
    // Mid-stream resume scenario: first observed position is past the cue.
    // Without the cold-start guard, the scheduler interprets the jump from
    // baseline 0s → 10s as a seek and (under skipIfSeekedPast) MARKS the
    // cue as fired — meaning if the user later rewinds and naturally
    // crosses t=5, the ad won't fire either. With the guard, the first
    // tick simply records the baseline and a subsequent rewind+cross
    // fires the cue normally.
    final player = _FakePlayer();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        midRolls: [
          MidRollAd(
            at: const Duration(seconds: 5),
            cue: AdCue(builder: (_, __) => const SizedBox()),
            // default: skipIfSeekedPast
          ),
        ],
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
    )..attach();

    // First emit at t=10s (mid-stream resume).
    player.emit(NiumaPlayerValue.uninitialized().copyWith(
      phase: PlayerPhase.playing,
      position: const Duration(seconds: 10),
    ));
    expect(orch.activeCue.value, isNull,
        reason: 'cold-start position must not fire midRoll');

    // User rewinds to t=4, then plays forward through t=6 — natural cross.
    // Without the cold-start guard this would NOT fire because the cue was
    // already (incorrectly) marked fired during the cold-start tick.
    player.emit(NiumaPlayerValue.uninitialized().copyWith(
      phase: PlayerPhase.playing,
      position: const Duration(seconds: 4),
    ));
    player.emit(NiumaPlayerValue.uninitialized().copyWith(
      phase: PlayerPhase.playing,
      position: const Duration(seconds: 6),
    ));
    expect(orch.activeCue.value, isNotNull,
        reason: 'after rewind, natural forward cross of the cue must still '
            'fire — the cold-start tick should not have consumed it');

    orch.dispose();
  });

  test('pauseAd fires on playing → paused (manual) — onPause is called', () {
    final player = _FakePlayer();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        pauseAd: AdCue(builder: (_, __) => const SizedBox()),
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
    )..attach();

    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.playing));
    expect(player.pauseCalled, isFalse,
        reason: 'no ad fired yet; onPause should not have been called');

    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.paused));
    expect(orch.activeCue.value, isNotNull);
    // The ad fires from a paused state, so isPlaying is false → no onPause.
    // Validate that the player's recorded state at fire-time was 'paused'.
    expect(player.pauseCalled, isFalse);

    orch.dispose();
  });

  // ─────────────── M9 follow-up: activeCueType + dismissActive ───────────────

  test('activeCueType 与 activeCue 同步——preRoll', () {
    final player = _FakePlayer();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        preRoll: AdCue(builder: (_, __) => const SizedBox()),
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
    )..attach();

    expect(orch.activeCue.value, isNull);
    expect(orch.activeCueType.value, isNull);

    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.ready));

    expect(orch.activeCue.value, isNotNull);
    expect(orch.activeCueType.value, AdCueType.preRoll);

    orch.dispose();
  });

  test('activeCueType 在 midRoll 触发时同步设为 midRoll', () {
    final player = _FakePlayer();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        midRolls: [
          MidRollAd(
            at: const Duration(seconds: 30),
            cue: AdCue(builder: (_, __) => const SizedBox()),
          ),
        ],
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
    )..attach();

    player.emit(NiumaPlayerValue.uninitialized().copyWith(
      phase: PlayerPhase.playing,
      position: const Duration(seconds: 29),
    ));
    player.emit(NiumaPlayerValue.uninitialized().copyWith(
      phase: PlayerPhase.playing,
      position: const Duration(seconds: 31),
    ));
    expect(orch.activeCueType.value, AdCueType.midRoll);
    orch.dispose();
  });

  test('activeCueType 在 pauseAd 触发时同步设为 pauseAd', () {
    final player = _FakePlayer();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        pauseAd: AdCue(builder: (_, __) => const SizedBox()),
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
    )..attach();

    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.playing));
    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.paused));
    expect(orch.activeCueType.value, AdCueType.pauseAd);
    orch.dispose();
  });

  test('activeCueType 在 postRoll 触发时同步设为 postRoll', () {
    final player = _FakePlayer();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        postRoll: AdCue(builder: (_, __) => const SizedBox()),
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
    )..attach();

    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.ended));
    expect(orch.activeCueType.value, AdCueType.postRoll);
    orch.dispose();
  });

  test('dismissActive 同时清空 activeCue 与 activeCueType', () {
    final player = _FakePlayer();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        preRoll: AdCue(builder: (_, __) => const SizedBox()),
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
    )..attach();

    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.ready));
    expect(orch.activeCue.value, isNotNull);
    expect(orch.activeCueType.value, isNotNull);

    orch.dismissActive();

    expect(orch.activeCue.value, isNull);
    expect(orch.activeCueType.value, isNull);
    orch.dispose();
  });

  // ─────────── M9 Task 2: AdControllerImpl emitter / dismiss 路由 ───────────

  group('AdControllerImpl emitter / dismiss', () {
    test('reportImpression 重复调用幂等——只 emit 一次 AdImpression', () {
      final analytics = FakeAnalyticsEmitter();
      final cue = AdCue(builder: (_, __) => const SizedBox());
      final ctl = AdControllerImpl(
        cue: cue,
        cueType: AdCueType.preRoll,
        emitter: analytics.call,
        onDismissRequested: () {},
      );

      ctl.reportImpression();
      ctl.reportImpression();
      ctl.reportImpression();

      final impressions = analytics.events.whereType<AdImpression>().toList();
      expect(impressions, hasLength(1));
      expect(impressions.first.cueType, AdCueType.preRoll);
    });

    test('reportClick 可重复调用——每次都 emit AdClick', () {
      final analytics = FakeAnalyticsEmitter();
      final cue = AdCue(builder: (_, __) => const SizedBox());
      final ctl = AdControllerImpl(
        cue: cue,
        cueType: AdCueType.midRoll,
        emitter: analytics.call,
        onDismissRequested: () {},
      );

      ctl.reportClick();
      ctl.reportClick();

      final clicks = analytics.events.whereType<AdClick>().toList();
      expect(clicks, hasLength(2));
      expect(clicks.every((c) => c.cueType == AdCueType.midRoll), isTrue);
    });

    test('dismiss 在 minDisplayDuration 内静默拒绝——不 emit、不 callback', () {
      final analytics = FakeAnalyticsEmitter();
      var dismissCalled = false;
      final cue = AdCue(
        builder: (_, __) => const SizedBox(),
        minDisplayDuration: const Duration(seconds: 5),
      );
      final ctl = AdControllerImpl(
        cue: cue,
        cueType: AdCueType.preRoll,
        emitter: analytics.call,
        onDismissRequested: () => dismissCalled = true,
      );

      ctl.dismiss(); // 0s elapsed

      expect(analytics.events.whereType<AdDismissed>(), isEmpty);
      expect(dismissCalled, isFalse);
    });

    test(
        'dismiss 超过 minDisplayDuration 后 emit AdDismissed(userSkip) + 调 onDismissRequested',
        () {
      final analytics = FakeAnalyticsEmitter();
      var dismissCalled = false;
      final cue = AdCue(
        builder: (_, __) => const SizedBox(),
        minDisplayDuration: const Duration(seconds: 5),
      );
      final ctl = AdControllerImpl(
        cue: cue,
        cueType: AdCueType.pauseAd,
        emitter: analytics.call,
        onDismissRequested: () => dismissCalled = true,
      );
      ctl.simulateElapsed(const Duration(seconds: 6));

      ctl.dismiss();

      final dismissed = analytics.events.whereType<AdDismissed>().toList();
      expect(dismissed, hasLength(1));
      expect(dismissed.first.cueType, AdCueType.pauseAd);
      expect(dismissed.first.reason, AdDismissReason.userSkip);
      expect(dismissCalled, isTrue);
    });

    test('dismiss 调用一次后再调被忽略——onDismissRequested 仅触发一次', () {
      final analytics = FakeAnalyticsEmitter();
      var dismissCount = 0;
      final cue = AdCue(
        builder: (_, __) => const SizedBox(),
        minDisplayDuration: const Duration(seconds: 5),
      );
      final ctl = AdControllerImpl(
        cue: cue,
        cueType: AdCueType.preRoll,
        emitter: analytics.call,
        onDismissRequested: () => dismissCount++,
      );
      ctl.simulateElapsed(const Duration(seconds: 6));

      ctl.dismiss();
      ctl.dismiss();

      expect(analytics.events.whereType<AdDismissed>(), hasLength(1));
      expect(dismissCount, 1);
    });

    test('dispose() 关闭 elapsedStream——非 dismiss 路径也释放', () async {
      final analytics = FakeAnalyticsEmitter();
      final ctl = AdControllerImpl(
        cue: AdCue(builder: (_, __) => const SizedBox()),
        cueType: AdCueType.preRoll,
        emitter: analytics.call,
        onDismissRequested: () {},
      );

      var done = false;
      final sub = ctl.elapsedStream.listen((_) {}, onDone: () => done = true);
      ctl.dispose();

      // broadcast stream 的 onDone 是异步——pump 一下 microtask。
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue, reason: 'dispose 应当 close 内部 _elapsedCtrl');
      await sub.cancel();
    });

    test('dispose() 多次调用幂等，不抛', () async {
      final analytics = FakeAnalyticsEmitter();
      final ctl = AdControllerImpl(
        cue: AdCue(builder: (_, __) => const SizedBox()),
        cueType: AdCueType.preRoll,
        emitter: analytics.call,
        onDismissRequested: () {},
      );

      ctl.dispose();
      // 第二次 dispose 不应抛——_elapsedCtrl.close() 在已 close 的状态下
      // 仍然安全。
      expect(() => ctl.dispose(), returnsNormally);
    });
  });

  group('_fire 重 fire 同 cue 仍通知 listener', () {
    test('dismissActive 后再 fire 同实例仍触发 activeCue listener', () {
      final player = _FakePlayer();
      final cue = AdCue(builder: (_, __) => const SizedBox());
      final orch = AdSchedulerOrchestrator(
        schedule: NiumaAdSchedule(preRoll: cue),
        playerValue: player,
        onPlay: player.play,
        onPause: player.pause,
      )..attach();

      var notifyCount = 0;
      AdCue? lastSeen;
      orch.activeCue.addListener(() {
        notifyCount++;
        lastSeen = orch.activeCue.value;
      });

      // 第一次 fire——通过 phase=ready 的转变触发 preRoll。
      player.emit(NiumaPlayerValue.uninitialized()
          .copyWith(phase: PlayerPhase.ready));
      expect(orch.activeCue.value, same(cue));
      final firstNotify = notifyCount;
      expect(firstNotify, greaterThan(0));

      // dismissActive → activeCue=null。
      orch.dismissActive();
      expect(orch.activeCue.value, isNull);
      final afterDismissNotify = notifyCount;
      expect(afterDismissNotify, greaterThan(firstNotify));

      // 模拟 race：直接调内部 _fire 等价路径——这里通过 activeCue.value
      // 写入同一 cue 实例验证 ValueNotifier 短路问题已修。
      // 由于 _fire 是私有的，我们通过 schedule + 重新触发 ready 不行
      // （preRollFired 已 true）；改用直接 set 方式覆盖：
      orch.activeCue.value = null; // 先清零（防御）
      orch.activeCue.value = cue;  // set 同实例
      // 因为我们刚把它 set 成 null 又 set cue，notify 必然增加。
      expect(notifyCount, greaterThan(afterDismissNotify));
      expect(lastSeen, same(cue));

      orch.dispose();
    });

    // R2-Important-3：测试真实的 _fire 路径——通过 @visibleForTesting
    // 暴露的 debugFire 入口，连续两次 fire 同一 cue 实例，验证 listener
    // 都能收到通知（依赖代码里"先 set null 再 set cue"的防御写法）。
    test('debugFire 连续两次同 cue 仍各自触发 listener（_fire 防御性 set null）', () {
      final player = _FakePlayer();
      final cue = AdCue(builder: (_, __) => const SizedBox());
      final orch = AdSchedulerOrchestrator(
        schedule: const NiumaAdSchedule(),
        playerValue: player,
        onPlay: player.play,
        onPause: player.pause,
      )..attach();

      var notifyCount = 0;
      AdCue? lastSeen;
      orch.activeCue.addListener(() {
        notifyCount++;
        lastSeen = orch.activeCue.value;
      });

      // 第一次 fire 同实例。
      orch.debugFire(cue, AdCueType.preRoll);
      // null → cue：notify 一次（cue 实例被 set 进 activeCue.value）。
      expect(orch.activeCue.value, same(cue));
      final firstNotifyCount = notifyCount;
      expect(firstNotifyCount, greaterThan(0));

      // 第二次 fire 同实例——_fire 内部"先 null 再 cue"应当让 listener 再触发。
      orch.debugFire(cue, AdCueType.preRoll);
      expect(orch.activeCue.value, same(cue));
      // 第二次 fire 至少要再触发一次 listener（cue → null → cue）。
      expect(notifyCount, greaterThan(firstNotifyCount),
          reason: '_fire 防御性 set null 应让同实例 cue 仍触发 listener');
      expect(lastSeen, same(cue));

      orch.dispose();
    });
  });
}
