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
  Duration _lastPos = Duration.zero;
  final Set<int> _midRollFired = {};
  int _pauseAdShownCount = 0;
  DateTime? _pauseAdLastShownAt;

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
    final v = playerValue.value;
    final phase = v.phase;

    final transitionedToReady =
        _lastPhase != PlayerPhase.ready && phase == PlayerPhase.ready;
    if (transitionedToReady && !_preRollFired && schedule.preRoll != null) {
      _preRollFired = true;
      _fire(schedule.preRoll!, AdCueType.preRoll);
    }

    // midRoll
    final pos = v.position;
    final delta = pos - _lastPos;
    final isLikelySeek = delta > const Duration(seconds: 2) ||
        delta < Duration.zero;

    for (var i = 0; i < schedule.midRolls.length; i++) {
      if (_midRollFired.contains(i)) continue;
      final mr = schedule.midRolls[i];
      final crossedNow = _lastPos < mr.at && pos >= mr.at;
      if (!crossedNow) continue;

      switch (mr.skipPolicy) {
        case MidRollSkipPolicy.fireOnce:
          _midRollFired.add(i);
          _fire(mr.cue, AdCueType.midRoll);
        case MidRollSkipPolicy.fireEachPass:
          _fire(mr.cue, AdCueType.midRoll);
        case MidRollSkipPolicy.skipIfSeekedPast:
          if (isLikelySeek) {
            _midRollFired.add(i); // mark fired to prevent later natural cross
          } else {
            _midRollFired.add(i);
            _fire(mr.cue, AdCueType.midRoll);
          }
      }
    }

    // pauseAd: detect manual pause (playing → paused).
    final justPaused = _lastPhase == PlayerPhase.playing &&
        phase == PlayerPhase.paused;
    if (justPaused && schedule.pauseAd != null && _shouldShowPauseAd()) {
      _fire(schedule.pauseAd!, AdCueType.pauseAd);
      _pauseAdShownCount++;
      _pauseAdLastShownAt = DateTime.now();
    }

    _lastPos = pos;
    _lastPhase = phase;
  }

  bool _shouldShowPauseAd() {
    switch (schedule.pauseAdShowPolicy) {
      case PauseAdShowPolicy.always:
        return true;
      case PauseAdShowPolicy.oncePerSession:
        return _pauseAdShownCount == 0;
      case PauseAdShowPolicy.cooldown:
        if (_pauseAdLastShownAt == null) return true;
        return DateTime.now().difference(_pauseAdLastShownAt!) >=
            schedule.pauseAdCooldown;
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
