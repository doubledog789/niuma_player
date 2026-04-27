// lib/src/orchestration/ad_schedule.dart
import 'package:flutter/widgets.dart';

/// Contract between an ad widget and the ad system.
///
/// Business widgets receive an [AdController] instance through the
/// [AdCue.builder] callback and use it to control their own dismissal and
/// to report telemetry events (impressions, clicks).  The concrete
/// implementation — [AdControllerImpl] — is owned by
/// [AdSchedulerOrchestrator] (Task 19) and is never constructed directly by
/// callers.
abstract class AdController {
  /// Closes the ad. Calls before [AdCue.minDisplayDuration] are silently
  /// ignored in release builds and asserted in debug builds.
  void dismiss();

  /// The instantaneous amount of time the ad has been displayed.
  Duration get elapsed;

  /// A broadcast stream that emits updated [elapsed] values on every tick.
  ///
  /// Typical use case: driving a countdown timer in the ad widget so the
  /// viewer can see how long until they are allowed to dismiss the overlay.
  Stream<Duration> get elapsedStream;

  /// Fires a fire-and-forget impression event.
  ///
  /// The [AdSchedulerOrchestrator] forwards this to [AnalyticsEmitter].
  /// Callers should invoke this once, as soon as the ad is visible.
  void reportImpression();

  /// Fires a fire-and-forget click event.
  ///
  /// The [AdSchedulerOrchestrator] forwards this to [AnalyticsEmitter].
  /// Callers should invoke this when the viewer interacts with the ad's
  /// call-to-action.
  void reportClick();
}

/// One displayable ad payload.
///
/// An [AdCue] is payload-agnostic: the actual widget is produced on demand by
/// [builder], which receives both a [BuildContext] and an [AdController].
/// Scheduling metadata ([minDisplayDuration], [timeout], [dismissOnTap]) is
/// declared alongside the builder so the ad system can enforce timing rules
/// without inspecting the widget tree.
@immutable
class AdCue {
  /// Creates an [AdCue].
  ///
  /// Only [builder] is required; all timing fields have sensible defaults.
  const AdCue({
    required this.builder,
    this.minDisplayDuration = const Duration(seconds: 5),
    this.timeout,
    this.dismissOnTap = false,
  });

  /// The widget render function for this ad.
  ///
  /// Receives a [BuildContext] and an [AdController].  The controller lets
  /// the widget dismiss itself and report telemetry events; use it instead of
  /// navigating or calling system-level pop operations directly.
  final Widget Function(BuildContext, AdController) builder;

  /// The minimum amount of time the ad must be shown before it can be
  /// dismissed.
  ///
  /// Calls to [AdController.dismiss] that arrive before this duration has
  /// elapsed are silently ignored in release builds and trigger an assertion
  /// failure in debug builds.  Defaults to five seconds.
  final Duration minDisplayDuration;

  /// Optional maximum display duration after which the ad is auto-dismissed.
  ///
  /// When [timeout] is non-null and the ad has been visible for this duration,
  /// the [AdSchedulerOrchestrator] dismisses it automatically.  A value of
  /// `null` (the default) means the ad never times out on its own.
  final Duration? timeout;

  /// Whether tapping anywhere on the ad overlay dismisses it.
  ///
  /// When `true`, the host ad overlay (rendered by `NiumaVideoPlayer` in M9)
  /// wraps the ad in a gesture detector that swallows taps and calls
  /// [AdController.dismiss]. When `false` (the default), taps pass through to
  /// whatever the [builder] renders — most ads provide their own close button.
  final bool dismissOnTap;
}

/// Controls how a mid-roll cue behaves when the viewer seeks or loops.
///
/// Passed as [MidRollAd.skipPolicy] to configure whether playback seeking
/// past the cue's [MidRollAd.at] position should suppress the ad.
enum MidRollSkipPolicy {
  /// Once the ad has been shown, it is never shown again — even after a
  /// rewind or loop.
  fireOnce,

  /// The ad fires every time playback crosses [MidRollAd.at], including
  /// after rewinds and in looping content.
  fireEachPass,

  /// If the viewer seeks past [MidRollAd.at] without crossing it through
  /// normal playback, the ad is suppressed for that seek.  This is the
  /// default and matches the behaviour of 抖音 / B 站 / 优酷.
  skipIfSeekedPast,
}

/// Controls how often the pause-ad is shown when the viewer manually pauses.
///
/// Assigned to [NiumaAdSchedule.pauseAdShowPolicy].
enum PauseAdShowPolicy {
  /// The pause ad is shown on every manual pause.
  always,

  /// The pause ad is shown at most once per playback session (default).
  oncePerSession,

  /// The pause ad is shown at most once per [NiumaAdSchedule.pauseAdCooldown]
  /// window.  The cooldown resets each time the ad is actually displayed.
  cooldown,
}

/// A mid-roll ad cue anchored to a specific timeline position.
///
/// [MidRollAd] pairs an [AdCue] payload with a playback [at] offset and a
/// [skipPolicy] that governs whether the ad fires when seeking jumps past it.
/// Instances are collected in [NiumaAdSchedule.midRolls], which must be sorted
/// by [at] in ascending order (caller responsibility).
@immutable
class MidRollAd {
  /// Creates a [MidRollAd].
  ///
  /// [at] and [cue] are required; [skipPolicy] defaults to
  /// [MidRollSkipPolicy.skipIfSeekedPast].
  const MidRollAd({
    required this.at,
    required this.cue,
    this.skipPolicy = MidRollSkipPolicy.skipIfSeekedPast,
  });

  /// The playback position at which this ad fires.
  ///
  /// The orchestrator compares the current position against [at] on each
  /// position tick.  Must be a positive, finite duration.
  final Duration at;

  /// The ad payload to display when playback reaches [at].
  final AdCue cue;

  /// Governs whether a seek past [at] suppresses the ad for that seek.
  ///
  /// Defaults to [MidRollSkipPolicy.skipIfSeekedPast].
  final MidRollSkipPolicy skipPolicy;
}

/// Declares all ad slots and pause-ad frequency for a single playback session.
///
/// [NiumaAdSchedule] is a pure data bag consumed by [AdSchedulerOrchestrator]
/// (Task 19).  It covers four distinct ad slots — pre-roll, mid-rolls, pause
/// and post-roll — plus a policy that limits how often the pause ad appears.
///
/// Example:
/// ```dart
/// NiumaAdSchedule(
///   preRoll: AdCue(builder: (ctx, ctrl) => MyPreRollWidget(ctrl)),
///   midRolls: [
///     MidRollAd(at: Duration(minutes: 5), cue: AdCue(builder: …)),
///   ],
///   pauseAdShowPolicy: PauseAdShowPolicy.cooldown,
///   pauseAdCooldown: Duration(minutes: 3),
/// )
/// ```
@immutable
class NiumaAdSchedule {
  /// Creates a [NiumaAdSchedule].
  ///
  /// All fields are optional; omitting them produces a schedule with no ads.
  const NiumaAdSchedule({
    this.preRoll,
    this.midRolls = const <MidRollAd>[],
    this.pauseAd,
    this.postRoll,
    this.pauseAdShowPolicy = PauseAdShowPolicy.oncePerSession,
    this.pauseAdCooldown = const Duration(minutes: 1),
  });

  /// Ad that fires on the first transition to `phase=ready`, before playback
  /// begins.  `null` means no pre-roll.
  final AdCue? preRoll;

  /// Timeline-anchored mid-roll cues.
  ///
  /// **Must be sorted by [MidRollAd.at] in ascending order** — this is the
  /// caller's responsibility.  The orchestrator performs a linear scan and
  /// relies on sort order for efficiency.  Defaults to an empty list.
  final List<MidRollAd> midRolls;

  /// Ad that fires when the viewer manually pauses playback.
  ///
  /// Display frequency is controlled by [pauseAdShowPolicy].  `null` means
  /// no pause ad.
  final AdCue? pauseAd;

  /// Ad that fires when `phase=ended` (playback reaches the end of content).
  /// `null` means no post-roll.
  final AdCue? postRoll;

  /// Frequency policy governing how often [pauseAd] is shown.
  ///
  /// Defaults to [PauseAdShowPolicy.oncePerSession].
  final PauseAdShowPolicy pauseAdShowPolicy;

  /// Minimum gap between two consecutive pause-ad displays.
  ///
  /// Only consulted when [pauseAdShowPolicy] is [PauseAdShowPolicy.cooldown].
  /// Defaults to one minute.
  final Duration pauseAdCooldown;
}
