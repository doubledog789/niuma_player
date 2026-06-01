import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player_example/niuma_ui/niuma_ui.dart';

void main() {
  test('AdImpression equality + hashcode', () {
    final a = AnalyticsEvent.adImpression(
      cueType: AdCueType.preRoll,
      durationShown: const Duration(seconds: 5),
    );
    final b = AnalyticsEvent.adImpression(
      cueType: AdCueType.preRoll,
      durationShown: const Duration(seconds: 5),
    );
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('AdDismissed reasons are distinct', () {
    expect(
      AnalyticsEvent.adDismissed(
        cueType: AdCueType.preRoll,
        reason: AdDismissReason.userSkip,
      ),
      isNot(equals(AnalyticsEvent.adDismissed(
        cueType: AdCueType.preRoll,
        reason: AdDismissReason.timeout,
      ))),
    );
  });
}
