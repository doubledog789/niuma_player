// test/orchestration/ad_schedule_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/ad_schedule.dart';

void main() {
  test('AdCue defaults', () {
    final cue = AdCue(builder: (_, __) => const SizedBox());
    expect(cue.minDisplayDuration, const Duration(seconds: 5));
    expect(cue.timeout, isNull);
    expect(cue.dismissOnTap, isFalse);
  });
}
