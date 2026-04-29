import 'package:flutter/foundation.dart';

/// Categorizes the placement of an ad within the content timeline.
enum AdCueType {
  /// Ad shown before content begins.
  preRoll,

  /// Ad shown at a scheduled mid-content position.
  midRoll,

  /// Ad triggered when the user pauses playback (not a pause action of an ad).
  pauseAd,

  /// Ad shown after content ends.
  postRoll,
}

/// Reason an ad was dismissed before its natural end.
enum AdDismissReason {
  /// User tapped the skip control.
  userSkip,

  /// Ad dismissed automatically after its display duration elapsed.
  timeout,

  /// Ad dismissed because the user tapped outside / on the dismiss area.
  dismissOnTap,
}

/// Structured event type emitted by niuma_player internals; consumed by a
/// user-supplied [AnalyticsEmitter].
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

/// Emitted when the orchestrator activates a cue (at-show, before any
/// impression has been counted).
final class AdScheduled extends AnalyticsEvent {
  const AdScheduled({required this.cueType, this.at});

  /// The placement category of the scheduled ad.
  final AdCueType cueType;

  /// Offset from the start of content at which the ad is scheduled; null for
  /// non-timeline placements such as [AdCueType.pauseAd].
  final Duration? at;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdScheduled && other.cueType == cueType && other.at == at;

  @override
  int get hashCode => Object.hash(cueType, at);
}

/// Fired when an ad becomes visible and begins its impression window.
final class AdImpression extends AnalyticsEvent {
  const AdImpression({required this.cueType, required this.durationShown});

  /// The placement category of the ad that was shown.
  final AdCueType cueType;

  /// How long the ad was visible before this event was emitted.
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

/// Fired when the user taps the ad's interactive (click-through) area.
final class AdClick extends AnalyticsEvent {
  const AdClick({required this.cueType});

  /// The placement category of the ad that was clicked.
  final AdCueType cueType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AdClick && other.cueType == cueType;

  @override
  int get hashCode => cueType.hashCode;
}

/// Fired when an ad is dismissed, either by user action or automatically.
final class AdDismissed extends AnalyticsEvent {
  const AdDismissed({required this.cueType, required this.reason});

  /// The placement category of the ad that was dismissed.
  final AdCueType cueType;

  /// The reason the ad was dismissed.
  final AdDismissReason reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdDismissed && other.cueType == cueType && other.reason == reason;

  @override
  int get hashCode => Object.hash(cueType, reason);
}
