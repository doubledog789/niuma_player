// lib/src/orchestration/ad_scheduler.dart
import 'dart:async';

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

    if (_lastPhase != PlayerPhase.ended &&
        phase == PlayerPhase.ended &&
        schedule.postRoll != null) {
      _fire(schedule.postRoll!, AdCueType.postRoll);
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

/// Concrete implementation of [AdController] owned by [AdSchedulerOrchestrator].
///
/// Enforces [AdCue.minDisplayDuration] before allowing dismissal: calls to
/// [dismiss] that arrive too early are silently ignored so a buggy ad widget
/// cannot crash playback.  The [simulateElapsed] hook is exposed for tests so
/// wall-clock timing does not have to be awaited in unit tests.
class AdControllerImpl implements AdController {
  /// Creates an [AdControllerImpl].
  ///
  /// [cue] is the cue this controller manages; [onDismiss] fires exactly once
  /// after a successful dismiss.
  AdControllerImpl({required this.cue, required this.onDismiss});

  /// The cue this controller is managing.
  final AdCue cue;

  /// Fires once when [dismiss] is allowed and succeeds.
  final VoidCallback onDismiss;

  final _elapsedCtrl = StreamController<Duration>.broadcast();
  final _start = DateTime.now();
  Duration _simulatedElapsed = Duration.zero;

  /// Whether this controller has been successfully dismissed.
  ///
  /// Flips to `true` exactly once after a successful [dismiss] call.
  /// Exposed as a public field for test assertions.
  bool dismissed = false;

  @override
  Duration get elapsed =>
      _simulatedElapsed > Duration.zero
          ? _simulatedElapsed
          : DateTime.now().difference(_start);

  @override
  Stream<Duration> get elapsedStream => _elapsedCtrl.stream;

  /// Overrides the wall-clock elapsed value for test purposes.
  ///
  /// When set to a non-zero value, [elapsed] returns this value instead of
  /// computing a real wall-clock difference.
  @visibleForTesting
  void simulateElapsed(Duration d) => _simulatedElapsed = d;

  @override
  void dismiss() {
    // Silently ignore (rather than throw / assert) so a buggy ad widget
    // doesn't crash playback.
    if (elapsed < cue.minDisplayDuration) return;
    if (dismissed) return;
    dismissed = true;
    onDismiss();
    _elapsedCtrl.close();
  }

  @override
  void reportImpression() {}

  @override
  void reportClick() {}
}
