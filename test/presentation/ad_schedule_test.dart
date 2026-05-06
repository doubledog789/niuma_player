import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/ad/ad_schedule.dart';

void main() {
  test('AdCue defaults', () {
    final cue = AdCue(builder: (_, __) => const SizedBox());
    expect(cue.minDisplayDuration, const Duration(seconds: 5));
    expect(cue.timeout, isNull);
    expect(cue.dismissOnTap, isFalse);
  });

  test('NiumaAdSchedule defaults', () {
    const s = NiumaAdSchedule();
    expect(s.preRoll, isNull);
    expect(s.midRolls, isEmpty);
    expect(s.pauseAd, isNull);
    expect(s.postRoll, isNull);
    expect(s.pauseAdShowPolicy, PauseAdShowPolicy.oncePerSession);
  });

  test('MidRollAd default skipPolicy is skipIfSeekedPast', () {
    final m = MidRollAd(
      at: const Duration(seconds: 30),
      cue: AdCue(builder: (_, __) => const SizedBox()),
    );
    expect(m.skipPolicy, MidRollSkipPolicy.skipIfSeekedPast);
    expect(m.at, const Duration(seconds: 30));
  });
}
