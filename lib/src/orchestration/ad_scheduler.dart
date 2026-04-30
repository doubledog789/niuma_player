import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/player_state.dart';
import '../observability/analytics_emitter.dart';
import '../observability/analytics_event.dart';
import 'ad_schedule.dart';

/// 基于 [ValueListenable<NiumaPlayerValue>] 的状态变化编排广告 cue 的触发。
///
/// 目前**仅**处理 preRoll 槽位：在首次进入 `phase == ready` 时触发一次
/// [AdCue]。midRoll、pauseAd、postRoll 的处理由后续任务（17、18、19）补齐。
class AdSchedulerOrchestrator {
  /// 创建一个 [AdSchedulerOrchestrator]。
  ///
  /// [schedule]、[playerValue]、[onPlay]、[onPause] 必填。
  /// [analytics] 可选——测试中传入 [FakeAnalyticsEmitter]。
  AdSchedulerOrchestrator({
    required this.schedule,
    required this.playerValue,
    required this.onPlay,
    required this.onPause,
    AnalyticsEmitter? analytics,
  }) : _analytics = analytics;

  /// 编排器所观察的、用于触发 cue 的广告排期。
  final NiumaAdSchedule schedule;

  /// 编排器监听播放器状态变化的 value source。
  final ValueListenable<NiumaPlayerValue> playerValue;

  /// 广告结束后用于恢复底层播放器播放的回调。
  final void Function() onPlay;

  /// 展示广告前用于暂停底层播放器的回调。
  final void Function() onPause;

  final AnalyticsEmitter? _analytics;

  /// 当前激活的广告 cue 的可观察通知器。
  ///
  /// 视图层订阅本通知器来渲染或关闭广告 overlay。`null` 表示当前
  /// 没有广告排播。
  final ValueNotifier<AdCue?> activeCue = ValueNotifier(null);

  /// 与 [activeCue] 同步切换的当前 cue 的位置类型通知器。
  ///
  /// `null` 表示当前没有广告排播。需要这个独立通知器，是因为视图层
  /// 在构造 `AdControllerImpl` 时必须知道 cue 类型，才能把
  /// `AdImpression` / `AdClick` / `AdDismissed` 事件标记到正确的
  /// [AdCueType] 上。
  final ValueNotifier<AdCueType?> activeCueType = ValueNotifier(null);

  PlayerPhase? _lastPhase;
  bool _preRollFired = false;
  Duration _lastPos = Duration.zero;

  /// 编排器是否已经观测到至少一个 position tick。
  ///
  /// 用于消除冷启动的误判：第一次 tick 时还没有基线，因此从
  /// `Duration.zero` 跳到例如 `t=10s`（中途断点续播）会被
  /// `delta > 2s || delta < 0` 启发式误识别为 seek。我们在第一次
  /// tick 上跳过 seek 检测分支，只记录 `_lastPos`。
  bool _haveSeenFirstPos = false;
  final Set<int> _midRollFired = {};
  int _pauseAdShownCount = 0;
  DateTime? _pauseAdLastShownAt;

  /// 开始监听 [playerValue] 的 phase 变化。
  ///
  /// 必须在构造之后调用一次。非幂等——调用两次会注册两个 listener。
  void attach() {
    playerValue.addListener(_onValue);
  }

  /// 停止监听 [playerValue] 并 dispose [activeCue] / [activeCueType] 通知器。
  void dispose() {
    playerValue.removeListener(_onValue);
    activeCue.dispose();
    activeCueType.dispose();
  }

  /// 关闭当前激活的 cue。
  ///
  /// 同时把 [activeCue] 与 [activeCueType] 清空。视图层在
  /// `AdController.dismiss` 走完后调用此方法，把"哪个 cue 在前台"
  /// 的事实从编排器视角擦除。重复调用是幂等的——`null` 状态下再
  /// 调一次不会触发额外通知。
  void dismissActive() {
    activeCue.value = null;
    activeCueType.value = null;
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

    // midRoll。第一次 tick 时完全跳过 seek 检测——还没有基线，否则
    // 例如 t=10s 的中途续播会被误判为 seek-past，把 t < 10s 的 cue
    // 错误地标记为已消费。
    final pos = v.position;
    if (_haveSeenFirstPos) {
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
              _midRollFired.add(i); // 标记为已触发，避免后续自然跨过时再触发
            } else {
              _midRollFired.add(i);
              _fire(mr.cue, AdCueType.midRoll);
            }
        }
      }
    }

    // pauseAd：检测手动暂停（playing → paused）。
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
    _haveSeenFirstPos = true;
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

  void _fire(AdCue cue, AdCueType type) {
    if (playerValue.value.isPlaying) onPause();
    activeCue.value = cue;
    activeCueType.value = type;
    _analytics?.call(AnalyticsEvent.adScheduled(cueType: type));
  }
}

/// 由 [AdSchedulerOrchestrator] 持有的 [AdController] 具体实现。
///
/// 在允许 dismiss 之前强制满足 [AdCue.minDisplayDuration]：来得过早的
/// [dismiss] 调用会被静默忽略，避免有 bug 的广告 widget 崩掉播放器。
/// 暴露 [simulateElapsed] 钩子是为了让单元测试不必等待 wall-clock 时间。
///
/// M9 起把 impression / click / dismiss 三类事件路由到调用方提供的
/// [AnalyticsEmitter]：宿主 overlay（[NiumaAdOverlay] 等）在每次 cue
/// 激活时构造一个新的 [AdControllerImpl]，把当前 [AdCueType] 与共享
/// emitter 注入进来；这个 controller 再把广告 widget 调出来的事件
/// 标注上正确的 cue 类型。
class AdControllerImpl implements AdController {
  /// 创建一个 [AdControllerImpl]。
  ///
  /// - [cue]：本 controller 管理的 cue；
  /// - [cueType]：本 cue 的位置类别，用来标注 emit 出的事件；
  /// - [emitter]：分析事件的 sink（通常由调用方传入的同一个
  ///   `AnalyticsEmitter` 复用）；
  /// - [onDismissRequested]：合法的 [dismiss] 调用之后触发——视图层
  ///   据此清空 `activeCue` 并恢复底层视频播放。
  AdControllerImpl({
    required this.cue,
    required this.cueType,
    required this.emitter,
    required this.onDismissRequested,
  });

  /// 本 controller 管理的 cue。
  final AdCue cue;

  /// 本 cue 的位置类别——emit 出的所有事件都用它标注。
  final AdCueType cueType;

  /// 分析事件的 sink。
  ///
  /// [reportImpression] / [reportClick] 与成功的 [dismiss] 路径都通过
  /// 这个 emitter 上报事件，调用方可在此把它转发给自家 analytics SDK。
  final AnalyticsEmitter emitter;

  /// 一次允许的 [dismiss] 之后触发——视图层据此清空 activeCue / 恢复
  /// 视频播放。仅触发一次，重复 dismiss 调用不会重复触发。
  final VoidCallback onDismissRequested;

  final _elapsedCtrl = StreamController<Duration>.broadcast();
  final _start = DateTime.now();
  Duration? _simulatedElapsed;
  bool _impressionReported = false;

  /// 本 controller 是否已被成功 dismiss。
  ///
  /// 在一次成功的 [dismiss] 调用后翻转为 `true`，仅一次。
  /// 作为 public 字段暴露，便于测试断言。
  bool dismissed = false;

  @override
  Duration get elapsed =>
      _simulatedElapsed ?? DateTime.now().difference(_start);

  @override
  Stream<Duration> get elapsedStream => _elapsedCtrl.stream;

  /// 出于测试目的覆盖 wall-clock 计算的 elapsed 值。
  ///
  /// 一旦设置（任意值，包括 [Duration.zero]），[elapsed] 返回该值，
  /// 不再计算真实的 wall-clock 差值。
  @visibleForTesting
  void simulateElapsed(Duration d) => _simulatedElapsed = d;

  @override
  void dismiss() {
    // 静默忽略（而不是 throw / assert），避免有 bug 的广告 widget
    // 把播放器搞崩。
    if (elapsed < cue.minDisplayDuration) return;
    if (dismissed) return;
    dismissed = true;
    emitter(AnalyticsEvent.adDismissed(
      cueType: cueType,
      reason: AdDismissReason.userSkip,
    ));
    onDismissRequested();
    _elapsedCtrl.close();
  }

  @override
  void reportImpression() {
    // 重复调用幂等：广告 widget 在每次 rebuild 都尝试上报 impression
    // 是常见错误，这里收口确保 analytics 只看到一次。
    if (_impressionReported) return;
    _impressionReported = true;
    emitter(AnalyticsEvent.adImpression(
      cueType: cueType,
      durationShown: elapsed,
    ));
  }

  @override
  void reportClick() {
    // click 不去重：观众可能反复点击 CTA 区域，每次都是有意义的信号。
    emitter(AnalyticsEvent.adClick(cueType: cueType));
  }
}
