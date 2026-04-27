// lib/src/orchestration/ad_scheduler.dart
import 'package:flutter/foundation.dart';

import '../domain/player_state.dart';
import '../observability/analytics_emitter.dart';
import '../observability/analytics_event.dart';
import 'ad_schedule.dart';

/// Orchestrates ad-cue firing based on changes to a [ValueListenable<NiumaPlayerValue>].
///
/// Currently handles **only** the preRoll slot: fires [AdCue] exactly once on
/// the first `phase == ready` transition. midRoll, pauseAd, and postRoll
/// handling are added in subsequent tasks (17, 18, 19).
class AdSchedulerOrchestrator {
  /// Creates an [AdSchedulerOrchestrator].
  ///
  /// [schedule], [playerValue], [onPlay], and [onPause] are required.
  /// [analytics] is optional — pass a [FakeAnalyticsEmitter] in tests.
  AdSchedulerOrchestrator({
    required this.schedule,
    required this.playerValue,
    required this.onPlay,
    required this.onPause,
    AnalyticsEmitter? analytics,
  }) : _analytics = analytics;

  /// The ad schedule this orchestrator watches for cues to fire.
  final NiumaAdSchedule schedule;

  /// The value source the orchestrator listens to for player state changes.
  final ValueListenable<NiumaPlayerValue> playerValue;

  /// Callback invoked to resume the underlying player after an ad finishes.
  final void Function() onPlay;

  /// Callback invoked to pause the underlying player before showing an ad.
  final void Function() onPause;

  final AnalyticsEmitter? _analytics;

  /// Observable notifier for the currently active ad cue.
  ///
  /// The widget layer subscribes to this notifier to render or dismiss the
  /// ad overlay. `null` means no ad is currently scheduled.
  final ValueNotifier<AdCue?> activeCue = ValueNotifier(null);

  PlayerPhase? _lastPhase;
  bool _preRollFired = false;

  /// Starts listening to [playerValue] for phase changes.
  ///
  /// Must be called once after construction. Not idempotent — calling twice
  /// adds a second listener.
  void attach() {
    playerValue.addListener(_onValue);
  }

  /// Stops listening to [playerValue] and disposes the [activeCue] notifier.
  void dispose() {
    playerValue.removeListener(_onValue);
    activeCue.dispose();
  }

  void _onValue() {
    final phase = playerValue.value.phase;
    final transitionedToReady =
        _lastPhase != PlayerPhase.ready && phase == PlayerPhase.ready;
    _lastPhase = phase;

    if (transitionedToReady && !_preRollFired && schedule.preRoll != null) {
      _preRollFired = true;
      _fire(schedule.preRoll!, AdCueType.preRoll);
    }
  }

  bool _wasPlaying = false;
  void _fire(AdCue cue, AdCueType type) {
    _wasPlaying = playerValue.value.isPlaying;
    if (_wasPlaying) onPause();
    activeCue.value = cue;
    _analytics?.call(AnalyticsEvent.adScheduled(cueType: type));
  }
}
