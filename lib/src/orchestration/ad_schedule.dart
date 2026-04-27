// lib/src/orchestration/ad_schedule.dart
import 'package:flutter/foundation.dart';
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
  /// When `true`, the [AdOverlay] wraps the ad in a gesture detector that
  /// swallows taps and calls [AdController.dismiss].  When `false` (the
  /// default), taps pass through to whatever the [builder] renders — most ads
  /// provide their own close button.
  final bool dismissOnTap;
}
