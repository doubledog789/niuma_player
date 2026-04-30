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
  });
}
