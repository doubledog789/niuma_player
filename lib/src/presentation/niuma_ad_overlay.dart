import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/player_state.dart';
import '../observability/analytics_emitter.dart';
import '../observability/analytics_event.dart';
import '../orchestration/ad_schedule.dart';
import '../orchestration/ad_scheduler.dart';
import 'niuma_player_controller.dart';

/// 广告 overlay：把 [AdSchedulerOrchestrator.activeCue] 翻译成
/// 屏幕上的真正 widget。
///
/// 行为契约：
/// - 监听 [AdSchedulerOrchestrator.activeCue]——`null` → 渲染
///   [SizedBox.shrink]；非 null → 实例化一个 `AdControllerImpl`、
///   按需暂停视频、跑 `cue.timeout` 倒计时、调 `cue.builder` 渲染。
/// - 当 cue 切回 null（外部 `dismissActive` 或 controller 自身路由的
///   合法 dismiss）：dispose 内部 `AdControllerImpl`、cancel timer，
///   并在 [pauseVideoWhileShowing] 为 true 且 cue 出现前视频在播时
///   恢复 `videoController.play()`。
/// - `cue.builder` 调用过程中如果抛异常：捕获、emit
///   [AnalyticsEvent.adDismissed]（reason: timeout，作为退化兼容
///   值——M9 的 [AdDismissReason] 暂未提供 `error`），同步把 overlay
///   清空、释放 controller 并恢复视频。
/// - `cue.dismissOnTap=true` 时整覆盖区可点击（透明 GestureDetector
///   叠在 builder 上方），调内部 controller 的 `dismiss()` 走完
///   `minDisplayDuration` 检查。
///
/// **注意**：本 widget 自身只触发**自动**关闭（timeout / builder 异常
/// / dismissOnTap）；广告 widget 主动调 `controller.dismiss()` 会经
/// `AdControllerImpl` 自身的 emit 路径，二者不重复。
class NiumaAdOverlay extends StatefulWidget {
  /// 创建一个 [NiumaAdOverlay]。
  const NiumaAdOverlay({
    super.key,
    required this.orchestrator,
    required this.videoController,
    required this.emitter,
    this.pauseVideoWhileShowing = true,
  });

  /// 提供 `activeCue` / `activeCueType` 流的编排器。
  final AdSchedulerOrchestrator orchestrator;

  /// 用来在 cue 出现 / 结束时控制底层视频播放的 controller。
  final NiumaPlayerController videoController;

  /// `AdImpression` / `AdClick` / `AdDismissed` 的目标 sink。
  final AnalyticsEmitter emitter;

  /// 广告显示期间是否自动暂停底层视频。默认 `true`。
  final bool pauseVideoWhileShowing;

  @override
  State<NiumaAdOverlay> createState() => _NiumaAdOverlayState();
}

class _NiumaAdOverlayState extends State<NiumaAdOverlay> {
  AdControllerImpl? _adCtrl;
  Timer? _timeoutTimer;

  /// 进入当前 cue 之前视频是否正在播。cue 走完后据此决定要不要恢复 play。
  bool _wasPlayingBeforeCue = false;

  /// 上一次观察到的 activeCue 引用——用来在 listener 触发时判断
  /// "新出现 vs 关闭"。
  AdCue? _lastCue;

  @override
  void initState() {
    super.initState();
    widget.orchestrator.activeCue.addListener(_onActiveCueChanged);
    // 如果挂载时已经有激活 cue（罕见但合法），也要对齐状态。
    if (widget.orchestrator.activeCue.value != null) {
      _onActiveCueChanged();
    }
  }

  @override
  void dispose() {
    widget.orchestrator.activeCue.removeListener(_onActiveCueChanged);
    _disposeAdCtrl();
    super.dispose();
  }

  void _disposeAdCtrl() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _adCtrl = null;
  }

  void _onActiveCueChanged() {
    final next = widget.orchestrator.activeCue.value;
    final prev = _lastCue;
    _lastCue = next;

    if (next != null && prev == null) {
      // 进入：新 cue 开始。
      _wasPlayingBeforeCue =
          widget.videoController.value.phase == PlayerPhase.playing;
      if (widget.pauseVideoWhileShowing) {
        widget.videoController.pause();
      }
      final cueType = widget.orchestrator.activeCueType.value ??
          AdCueType.preRoll;
      _adCtrl = AdControllerImpl(
        cue: next,
        cueType: cueType,
        emitter: widget.emitter,
        onDismissRequested: () {
          // controller.dismiss() 内部已 emit AdDismissed；这里只需要
          // 把 overlay 状态收回，让 ValueNotifier 通知到 listener，再走
          // 一遍我们的离开分支。
          widget.orchestrator.dismissActive();
        },
      );
      // timeout 自动关闭。
      final timeout = next.timeout;
      if (timeout != null) {
        _timeoutTimer = Timer(timeout, () {
          if (!mounted) return;
          if (widget.orchestrator.activeCue.value != next) return;
          widget.emitter(AnalyticsEvent.adDismissed(
            cueType: cueType,
            reason: AdDismissReason.timeout,
          ));
          widget.orchestrator.dismissActive();
        });
      }
      setState(() {});
    } else if (next == null && prev != null) {
      // 离开：cue 结束。dispose 内部 controller，恢复视频。
      _disposeAdCtrl();
      if (widget.pauseVideoWhileShowing && _wasPlayingBeforeCue) {
        widget.videoController.play();
      }
      _wasPlayingBeforeCue = false;
      if (mounted) setState(() {});
    } else if (next != null && prev != null && !identical(next, prev)) {
      // 切换：罕见，但 cue 直接换成另一个 cue（编排器 race）——
      // 安全起见走"关闭旧 + 打开新"。
      _disposeAdCtrl();
      _lastCue = null; // 强制下次 _onActiveCueChanged 视为"新出现"。
      _onActiveCueChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cue = widget.orchestrator.activeCue.value;
    final adCtrl = _adCtrl;
    if (cue == null || adCtrl == null) return const SizedBox.shrink();

    Widget child;
    try {
      child = cue.builder(context, adCtrl);
    } catch (e, st) {
      // builder 抛异常——M9 的 AdDismissReason 没有 error 选项，复用 timeout
      // 作为兼容值；errorBuilder 之外的所有意外退场都标记成 timeout。
      debugPrint('[niuma_player] AdCue.builder 抛异常: $e\n$st');
      // 在 build 期间不能直接 setState；post-frame 走清理 + emit。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.orchestrator.activeCue.value != cue) return;
        widget.emitter(AnalyticsEvent.adDismissed(
          cueType: adCtrl.cueType,
          reason: AdDismissReason.timeout,
        ));
        widget.orchestrator.dismissActive();
      });
      return const SizedBox.shrink();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (cue.dismissOnTap)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: adCtrl.dismiss,
            ),
          ),
      ],
    );
  }
}
