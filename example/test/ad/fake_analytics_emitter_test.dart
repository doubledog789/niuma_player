import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player_example/niuma_ui/niuma_ui.dart';

void main() {
  test('FakeAnalyticsEmitter records events in order', () {
    final fake = FakeAnalyticsEmitter();
    fake.call(const AnalyticsEvent.adClick(cueType: AdCueType.preRoll));
    fake.call(const AnalyticsEvent.adImpression(
      cueType: AdCueType.preRoll,
      durationShown: Duration(seconds: 5),
    ));
    expect(fake.events, hasLength(2));
    expect(fake.events.first, isA<AdClick>());
  });

  test('FakeAnalyticsEmitter.clear empties log', () {
    final fake = FakeAnalyticsEmitter()
      ..call(const AnalyticsEvent.adClick(cueType: AdCueType.preRoll));
    fake.clear();
    expect(fake.events, isEmpty);
  });
}
