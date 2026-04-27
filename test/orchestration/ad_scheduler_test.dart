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
}
