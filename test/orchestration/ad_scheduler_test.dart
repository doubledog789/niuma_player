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

    // t=31s; fire.
    player.emit(NiumaPlayerValue.uninitialized().copyWith(
      phase: PlayerPhase.playing,
      position: const Duration(seconds: 31),
    ));
    expect(orch.activeCue.value, isNotNull);
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
    final ctl = AdControllerImpl(cue: cue, onDismiss: () {});
    ctl.dismiss(); // 0s elapsed
    expect(ctl.dismissed, isFalse, reason: 'release builds silently ignore');
  });

  test('AdController.dismiss after minDisplayDuration completes', () {
    final cue = AdCue(
      builder: (_, __) => const SizedBox(),
      minDisplayDuration: const Duration(seconds: 5),
    );
    var dismissed = false;
    final ctl = AdControllerImpl(cue: cue, onDismiss: () {
      dismissed = true;
    });
    ctl.simulateElapsed(const Duration(seconds: 6));
    ctl.dismiss();
    expect(dismissed, isTrue);
  });
}
