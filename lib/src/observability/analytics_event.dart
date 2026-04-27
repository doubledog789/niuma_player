// lib/src/observability/analytics_event.dart
import 'package:flutter/foundation.dart';

enum AdCueType { preRoll, midRoll, pauseAd, postRoll }
enum AdDismissReason { userSkip, timeout, dismissOnTap }

@immutable
sealed class AnalyticsEvent {
  const AnalyticsEvent();

  const factory AnalyticsEvent.adScheduled({
    required AdCueType cueType,
    Duration? at,
  }) = AdScheduled;

  const factory AnalyticsEvent.adImpression({
    required AdCueType cueType,
    required Duration durationShown,
  }) = AdImpression;

  const factory AnalyticsEvent.adClick({
    required AdCueType cueType,
  }) = AdClick;

  const factory AnalyticsEvent.adDismissed({
    required AdCueType cueType,
    required AdDismissReason reason,
  }) = AdDismissed;
}

final class AdScheduled extends AnalyticsEvent {
  const AdScheduled({required this.cueType, this.at});
  final AdCueType cueType;
  final Duration? at;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdScheduled && other.cueType == cueType && other.at == at;

  @override
  int get hashCode => Object.hash(cueType, at);
}

final class AdImpression extends AnalyticsEvent {
  const AdImpression({required this.cueType, required this.durationShown});
  final AdCueType cueType;
  final Duration durationShown;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdImpression &&
          other.cueType == cueType &&
          other.durationShown == durationShown;

  @override
  int get hashCode => Object.hash(cueType, durationShown);
}

final class AdClick extends AnalyticsEvent {
  const AdClick({required this.cueType});
  final AdCueType cueType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AdClick && other.cueType == cueType;

  @override
  int get hashCode => cueType.hashCode;
}

final class AdDismissed extends AnalyticsEvent {
  const AdDismissed({required this.cueType, required this.reason});
  final AdCueType cueType;
  final AdDismissReason reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdDismissed && other.cueType == cueType && other.reason == reason;

  @override
  int get hashCode => Object.hash(cueType, reason);
}
