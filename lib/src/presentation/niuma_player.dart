import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../domain/gesture_kind.dart';
import '../domain/player_state.dart';
import '../observability/analytics_emitter.dart';
import '../orchestration/ad_schedule.dart';
import '../orchestration/ad_scheduler.dart';
import 'controls/pip_button.dart';
import 'niuma_ad_overlay.dart';
import 'niuma_control_bar.dart';
import 'niuma_danmaku_controller.dart';
import 'niuma_danmaku_overlay.dart';
import 'niuma_danmaku_scope.dart';
import 'niuma_fullscreen_page.dart' show NiumaFullscreenScope;
import 'niuma_gesture_layer.dart';
import 'niuma_player_controller.dart';
import 'niuma_player_theme.dart';
import 'niuma_player_view.dart';

/// niuma_player 一体化默认播放组件。
///
/// 这是 90% 用户应该使用的入口：传一个 [NiumaPlayerController]，
/// 拿到一个完整的播放界面：
/// - 底部 [NiumaControlBar]（B 站风格密集底栏）
/// - [controlsAutoHideAfter] 时长不操作后自动隐藏控件
/// - 任意点击切换控件显示 / 隐藏
/// - `phase=paused` 时强制显示控件（不会"暂停了又找不到按钮"）
/// - 可选广告 [NiumaAdOverlay]——传 [adSchedule] 即激活
///
/// 自定义需求超过这套预设时：
/// 1. 上层包一层 [NiumaPlayerThemeData] 调主题；
/// 2. 自己拿原子控件（[PlayPauseButton] / [ScrubBar] / [TimeDisplay] /
///    ...）+ [NiumaPlayerView] 拼布局——本组件就是参考实现。
///
/// **Auto-hide 状态机**：
/// - 进入 `playing` 时启动 [controlsAutoHideAfter] 计时器；超时即隐藏。
/// - 进入 `paused` 时强制显示控件，并取消计时器。
/// - 用户点击视频区翻转显示状态；翻回显示且仍在 `playing` 时重启计时器。
/// - 广告 cue 进入时强制隐藏控件、暂停计时器（让 overlay 接管视野）；
///   cue 离开时恢复显示状态，按当前 phase 决定是否重启计时器。
class NiumaPlayer extends StatefulWidget {
  /// 创建一个 [NiumaPlayer]。
  const NiumaPlayer({
    super.key,
    required this.controller,
    this.theme,
    this.adSchedule,
    this.adAnalyticsEmitter,
    this.pauseVideoDuringAd = true,
    this.controlsAutoHideAfter = const Duration(seconds: 5),
    this.danmakuController,
    this.gesturesEnabledInline = false,
    this.disabledGestures = const {},
    this.gestureHudBuilder,
  });

  /// 实际驱动播放的 controller。所有内部子组件共享同一实例。
  final NiumaPlayerController controller;

  /// 可选 UI 主题。非空时本组件在内部 build 顶上自动包一层
  /// [NiumaPlayerThemeData]——上层无需手动嵌套。
  final NiumaPlayerTheme? theme;

  /// 可选广告排期。非空时构造内部 [AdSchedulerOrchestrator] +
  /// [NiumaAdOverlay]，按排期触发广告；为 `null` 时零额外开销，
  /// 不创建编排器、不渲染 overlay。
  final NiumaAdSchedule? adSchedule;

  /// 广告事件 sink。`null` 时使用 noop emitter（事件被丢弃）。
  final AnalyticsEmitter? adAnalyticsEmitter;

  /// 广告显示期间是否暂停底层视频。默认 `true`。
  final bool pauseVideoDuringAd;

  /// 进入 `playing` 后多久没有用户交互自动隐藏控件。默认 5s。
  /// 设为 [Duration.zero] 视为"永不自动隐藏"——控件永远可见。
  final Duration controlsAutoHideAfter;

  /// 可选弹幕 controller。传入即自动叠加 [NiumaDanmakuOverlay] 与
  /// 注入 [NiumaDanmakuScope]，让控件条里的 [DanmakuButton] 可点。
  final NiumaDanmakuController? danmakuController;

  /// 是否在 inline 场景启用手势（默认 false）。全屏页内永远启用（M13 默认行为）。
  final bool gesturesEnabledInline;

  /// 黑名单：不触发的手势类型。
  final Set<GestureKind> disabledGestures;

  /// HUD 自定义 builder。null = 用默认 [NiumaGestureHud]。
  final GestureHudBuilder? gestureHudBuilder;

  @override
  State<NiumaPlayer> createState() => _NiumaPlayerState();
}

class _NiumaPlayerState extends State<NiumaPlayer> {
  /// 当前是否显示控件栏。`true` 即可见，`false` 即淡出。
  bool _controlsVisible = true;

  /// auto-hide 计时器；每次进入 `playing` / 用户交互都会重置。
  Timer? _hideTimer;

  /// 可选广告编排器；当 [NiumaPlayer.adSchedule] 非空时构造，dispose 时清理。
  AdSchedulerOrchestrator? _orchestrator;

  /// 上一次观察到的 phase——用于在 paused → playing 转换时启动计时器。
  PlayerPhase? _lastPhase;

  /// 上一次观察到的 active cue——用于在 cue 出现 / 消失时同步控件状态。
  AdCue? _lastCue;

  /// 最新一次"我希望 controls 切到 visible 还是 hidden"的意图——
  /// `null` 表示"目前没有 pending 切换请求"。
  ///
  /// `_setControlsVisible` 在 framework 锁定阶段会 enqueue 一个
  /// post-frame callback；如果在 callback fire 前又来一次反向切换，
  /// 旧 callback 仍然按闭包里的 `visible` 参数执行——会覆盖新意图。
  /// 把意图存这里，post-frame 再读字段，确保按"最后一次写入"生效。
  bool? _pendingVisibleIntent;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onValueChanged);
    _setupOrchestrator(widget);
    // 首帧也对齐 phase——挂载时已经在 playing 时立即启动计时。
    _onValueChanged();
  }

  @override
  void didUpdateWidget(covariant NiumaPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = oldWidget.controller != widget.controller;
    final scheduleChanged = oldWidget.adSchedule != widget.adSchedule ||
        oldWidget.adAnalyticsEmitter != widget.adAnalyticsEmitter;

    if (controllerChanged) {
      // detach 旧 controller，把 listener / orchestrator 全重建在新
      // controller 上——否则 phase / activeCue 都还在 stale 实例上。
      oldWidget.controller.removeListener(_onValueChanged);
      _teardownOrchestrator();
      _setupOrchestrator(widget);
      widget.controller.addListener(_onValueChanged);
      _lastPhase = null;
      _lastCue = null;
      _onValueChanged();
    } else if (scheduleChanged) {
      // controller 没换但 adSchedule 换了——只重建 orchestrator。
      _teardownOrchestrator();
      _setupOrchestrator(widget);
      _lastCue = null;
    }

    // controlsAutoHideAfter 改了——cancel 旧计时，按当前 phase 决定是否
    // 用新值重启。pauseVideoDuringAd 改了只影响下次 cue 进入的行为，
    // 已激活的 cue 状态不重置（语义上把"切换时机点"留给下次更安全），
    // 所以这里只 diff controlsAutoHideAfter。
    if (oldWidget.controlsAutoHideAfter != widget.controlsAutoHideAfter) {
      _hideTimer?.cancel();
      _hideTimer = null;
      if (widget.controller.value.phase == PlayerPhase.playing &&
          _orchestrator?.activeCue.value == null) {
        _scheduleAutoHide();
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onValueChanged);
    _teardownOrchestrator();
    super.dispose();
  }

  /// 按当前 [widget] 配置构建一个新的 [_orchestrator]——`adSchedule == null`
  /// 时不创建。
  void _setupOrchestrator(NiumaPlayer w) {
    final schedule = w.adSchedule;
    if (schedule == null) {
      _orchestrator = null;
      return;
    }
    _orchestrator = AdSchedulerOrchestrator(
      schedule: schedule,
      playerValue: w.controller,
      onPlay: () => w.controller.play(),
      onPause: () => w.controller.pause(),
      analytics: w.adAnalyticsEmitter,
    );
    _orchestrator!.attach();
    _orchestrator!.activeCue.addListener(_onActiveCueChanged);
  }

  /// 取下监听并 dispose 当前 [_orchestrator]——若为 null 则 no-op。
  void _teardownOrchestrator() {
    final orch = _orchestrator;
    if (orch == null) return;
    orch.activeCue.removeListener(_onActiveCueChanged);
    orch.dispose();
    _orchestrator = null;
  }

  void _onValueChanged() {
    final v = widget.controller.value;
    final phase = v.phase;

    if (phase == PlayerPhase.paused) {
      // paused → 永远显示控件，并取消计时。
      _hideTimer?.cancel();
      _hideTimer = null;
      _setControlsVisible(true);
    } else if (phase == PlayerPhase.playing) {
      // 进入 playing：如果之前是别的 phase（含 idle / opening / ready），
      // 启动 auto-hide 倒计时。
      if (_lastPhase != PlayerPhase.playing) {
        _scheduleAutoHide();
      }
    }
    _lastPhase = phase;
  }

  void _onActiveCueChanged() {
    final cue = _orchestrator?.activeCue.value;
    if (cue != null && _lastCue == null) {
      // 新 cue 进入——隐藏控件让 overlay 接管，取消计时。
      _hideTimer?.cancel();
      _setControlsVisible(false);
    } else if (cue == null && _lastCue != null) {
      // cue 离开——恢复显示并按 phase 决定是否启动计时。
      _setControlsVisible(true);
      if (widget.controller.value.phase == PlayerPhase.playing) {
        _scheduleAutoHide();
      }
    }
    _lastCue = cue;
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    final after = widget.controlsAutoHideAfter;
    if (after <= Duration.zero) return;
    _hideTimer = Timer(after, () {
      if (!mounted) return;
      // 二次校验：广告活跃 / 暂停状态下不强制隐藏。
      if (_orchestrator?.activeCue.value != null) return;
      if (widget.controller.value.phase == PlayerPhase.paused) return;
      _setControlsVisible(false);
    });
  }

  /// 把 `_controlsVisible` 切到 [visible]——必要时延后到下一帧避免
  /// "framework is locked"。
  ///
  /// 背景：[NiumaPlayerController] 是 sync ValueNotifier；监听器在
  /// build / layout / paint 阶段都可能 fire。直接 setState 会撞 framework
  /// lock。这里检测 [SchedulerBinding.schedulerPhase]，必要时用
  /// post-frame callback 延后。
  ///
  /// 多次调用合并：post-frame callback 用 [_pendingVisibleIntent] 字段
  /// 读最新意图，避免连发两次反向切换时旧 callback 覆盖新意图。
  void _setControlsVisible(bool visible) {
    if (_controlsVisible == visible) return;
    // 测试时可以通过 [debugSchedulerPhaseOverride] 模拟特定 phase 触发；
    // 生产代码读真实 [SchedulerBinding.schedulerPhase]。
    final phase = debugSchedulerPhaseOverride ??
        SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      final hadPending = _pendingVisibleIntent != null;
      _pendingVisibleIntent = visible;
      // 仅在没有 pending callback 时 enqueue——再次切换只更新 field。
      if (!hadPending) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            _pendingVisibleIntent = null;
            return;
          }
          final intent = _pendingVisibleIntent;
          _pendingVisibleIntent = null;
          if (intent == null) return;
          if (_controlsVisible == intent) return;
          setState(() => _controlsVisible = intent);
        });
      }
    } else {
      _pendingVisibleIntent = null;
      setState(() => _controlsVisible = visible);
    }
  }

  // ───────────── @visibleForTesting accessors ─────────────
  // 这一组 getter / wrapper 只供单测访问内部状态——日常代码不要用。

  /// 测试用：当前 `_controlsVisible` 字段值。
  @visibleForTesting
  bool get debugControlsVisible => _controlsVisible;

  /// 测试用：当前 `_pendingVisibleIntent` 字段值——`null` 表示无 pending。
  @visibleForTesting
  bool? get debugPendingVisibleIntent => _pendingVisibleIntent;

  /// 测试用：直接调 [_setControlsVisible]——便于覆盖 build 阶段的
  /// post-frame 入队分支。
  @visibleForTesting
  void debugSetControlsVisible(bool visible) => _setControlsVisible(visible);

  void _onTapVideo() {
    // 广告 cue 活跃时把 tap 让给 NiumaAdOverlay（它自己有 dismissOnTap
    // 行为）——本控件层不切换可见，避免拦截 cue 关闭手势。
    if (_orchestrator?.activeCue.value != null) return;
    final next = !_controlsVisible;
    // 走 _setControlsVisible 而不是直接 setState——一致性优先：
    // 理论上 build 阶段不会有 tap，但走统一入口可以让后续的"build
    // 阶段保护"逻辑（post-frame 延后 + intent 合并）天然覆盖到 tap 路径。
    _setControlsVisible(next);
    if (next && widget.controller.value.phase == PlayerPhase.playing) {
      _scheduleAutoHide();
    }
  }

  /// 任何 pointer 落在本 NiumaPlayer 子树时调用——拖进度条 / 点控件按钮
  /// 等"用户活跃中"信号让 auto-hide 计时器重新计时，避免拖动期间满 5s
  /// 突然隐藏控件。
  ///
  /// 仅在 `_controlsVisible == true` 且 phase=playing 时重启计时——隐藏
  /// 状态下交互通常意味着用户先 tap 显示了控件，再后续操作；那次 tap
  /// 已经走 [_onTapVideo] 安排好计时，这里不重复。
  void _onUserActivity() {
    if (!_controlsVisible) return;
    if (widget.controller.value.phase != PlayerPhase.playing) return;
    _scheduleAutoHide();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Builder(
      builder: (innerContext) {
        // 在内层 Builder 中读 theme，确保如果外层 widget.theme 注入了
        // NiumaPlayerThemeData，本层读到的就是新主题。
        final theme = NiumaPlayerTheme.of(innerContext);
        final fadeDuration = theme.fadeInDuration;

        // 外层 Listener 不消费事件（translucent 行为靠 onPointerSignal）
        // ——onPointerDown / onPointerMove 命中本 widget 子树任意位置都
        // 重置 auto-hide 计时器：拖进度条 / 点按钮 / 音量条等期间持续保活
        // 控件可见，避免"用户还在操作但 5s 后突然消失"的不合理体验。
        // controller.value 变化以外的交互（仅本地 widget state 变化的拖动）
        // 才需要这一层兜底；不做的话 ScrubBar drag 期间 _onValueChanged
        // 不 fire，timer 一直跑到底。
        return Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: (_) => _onUserActivity(),
          onPointerMove: (_) => _onUserActivity(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NiumaPlayerView(widget.controller),
              // 手势层：放在视频之上、控件之下。
              // M9 既有"单击切控件显隐"行为通过 onTap: _onTapVideo 透传保留。
              // enabled：全屏 scope 内永远 true；inline 场景看 gesturesEnabledInline。
              Positioned.fill(
                child: NiumaGestureLayer(
                  controller: widget.controller,
                  enabled: NiumaFullscreenScope.maybeOf(innerContext) != null ||
                      widget.gesturesEnabledInline,
                  disabledGestures: widget.disabledGestures,
                  hudBuilder: widget.gestureHudBuilder,
                  onTap: _onTapVideo,
                  child: const SizedBox.expand(),
                ),
              ),
              if (widget.danmakuController != null)
                Positioned.fill(
                  child: NiumaDanmakuOverlay(
                    video: widget.controller,
                    danmaku: widget.danmakuController!,
                  ),
                ),
              AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: fadeDuration,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: NiumaControlBar(controller: widget.controller),
                  ),
                ),
              ),
              // M12: 右上角 PipButton 浮层，跟控件条 auto-hide 同步
              AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: fadeDuration,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: PipButton(controller: widget.controller),
                      ),
                    ),
                  ),
                ),
              ),
              if (_orchestrator != null)
                Positioned.fill(
                  child: NiumaAdOverlay(
                    orchestrator: _orchestrator!,
                    videoController: widget.controller,
                    emitter: widget.adAnalyticsEmitter ?? _noopEmitter,
                    pauseVideoWhileShowing: widget.pauseVideoDuringAd,
                  ),
                ),
            ],
          ),
        );
      },
    );

    // 包一层 NiumaPlayerConfigScope，让子树（特别是 FullscreenButton）
    // 在 push 全屏 route 时能读到外层 NiumaPlayer 的全部配置——避免
    // 全屏页内部的 NiumaPlayer 丢失 adSchedule / theme / autoHide 等
    // 关键 props。
    content = NiumaPlayerConfigScope(
      adSchedule: widget.adSchedule,
      adAnalyticsEmitter: widget.adAnalyticsEmitter,
      pauseVideoDuringAd: widget.pauseVideoDuringAd,
      controlsAutoHideAfter: widget.controlsAutoHideAfter,
      theme: widget.theme,
      danmakuController: widget.danmakuController,
      disabledGestures: widget.disabledGestures,
      gestureHudBuilder: widget.gestureHudBuilder,
      gesturesEnabledInline: widget.gesturesEnabledInline,
      child: content,
    );

    if (widget.danmakuController != null) {
      content = NiumaDanmakuScope(
        controller: widget.danmakuController!,
        child: content,
      );
    }

    if (widget.theme != null) {
      content = NiumaPlayerThemeData(data: widget.theme!, child: content);
    }
    return content;
  }
}

/// 把外层 [NiumaPlayer] 的关键配置注入子树的 [InheritedWidget]。
///
/// 这是为 [FullscreenButton] push 全屏 route 时**透传配置**而准备的：
/// 子树拿不到 widget 实例，但能读到本 marker，从而把外层用户配的
/// `adSchedule` / `adAnalyticsEmitter` / `pauseVideoDuringAd` /
/// `controlsAutoHideAfter` / `theme` 一起带进全屏页。
///
/// 不持有 [NiumaPlayerController]——controller 是必须显式传的，子树
/// 已经能直接拿到，不需要从这里读。
///
/// **使用约束**：[updateShouldNotify] 用 `==` 对所有字段做相等比较，
/// 但 [NiumaAdSchedule] / [AnalyticsEmitter] / [NiumaPlayerTheme] 这
/// 几个对象通常不实现结构相等（identity equal）——如果 host 在每次
/// 构建 [NiumaPlayer] 时都 new 一个新对象传进来，本 scope 的依赖者
/// 会被无谓地重建。建议把 `adSchedule` / `adAnalyticsEmitter` /
/// `theme` 缓存为 `const` 或在 [State] 里作为 final 字段持有。
///
/// **不导出**：本类仅在内部使用（[NiumaPlayer.build] 注入，
/// [FullscreenButton._onPressed] 读取），不属于公开 API。单测如需直接
/// 操作通过 `package:niuma_player/src/presentation/niuma_player.dart`
/// 的内部路径 import。
class NiumaPlayerConfigScope extends InheritedWidget {
  /// 构造一个 [NiumaPlayerConfigScope]。
  const NiumaPlayerConfigScope({
    super.key,
    required this.adSchedule,
    required this.adAnalyticsEmitter,
    required this.pauseVideoDuringAd,
    required this.controlsAutoHideAfter,
    required this.theme,
    required this.danmakuController,
    required this.disabledGestures,
    required this.gestureHudBuilder,
    required this.gesturesEnabledInline,
    required super.child,
  });

  /// 外层 NiumaPlayer 配置的广告排期（可空）。
  final NiumaAdSchedule? adSchedule;

  /// 外层 NiumaPlayer 配置的广告分析 emitter（可空）。
  final AnalyticsEmitter? adAnalyticsEmitter;

  /// 外层 NiumaPlayer 配置的"广告显示期间是否暂停底层视频"。
  final bool pauseVideoDuringAd;

  /// 外层 NiumaPlayer 配置的 auto-hide 时长。
  final Duration controlsAutoHideAfter;

  /// 外层 NiumaPlayer 配置的可选主题。
  final NiumaPlayerTheme? theme;

  /// 可选弹幕 controller，由 [NiumaPlayer] 透传给 [FullscreenButton]，
  /// push 全屏页时一并传到 [NiumaFullscreenPage] 内的 [NiumaPlayer]。
  final NiumaDanmakuController? danmakuController;

  /// M13: 手势黑名单（透给全屏页）。
  final Set<GestureKind> disabledGestures;

  /// M13: HUD builder（透给全屏页）。
  final GestureHudBuilder? gestureHudBuilder;

  /// M13: inline 启用手势（全屏页通常不读这字段——全屏永远开）。
  final bool gesturesEnabledInline;

  /// 找最近的 [NiumaPlayerConfigScope]——存在即返回；不存在返回 null。
  static NiumaPlayerConfigScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NiumaPlayerConfigScope>();
  }

  @override
  bool updateShouldNotify(NiumaPlayerConfigScope oldWidget) =>
      adSchedule != oldWidget.adSchedule ||
      adAnalyticsEmitter != oldWidget.adAnalyticsEmitter ||
      pauseVideoDuringAd != oldWidget.pauseVideoDuringAd ||
      controlsAutoHideAfter != oldWidget.controlsAutoHideAfter ||
      theme != oldWidget.theme ||
      danmakuController != oldWidget.danmakuController ||
      oldWidget.disabledGestures != disabledGestures ||
      oldWidget.gestureHudBuilder != gestureHudBuilder ||
      oldWidget.gesturesEnabledInline != gesturesEnabledInline;
}

/// noop analytics emitter——用户不传 emitter 时把事件丢掉，避免广告
/// overlay 内部 null 校验。
void _noopEmitter(Object event) {}

/// 测试用：当非 `null` 时覆盖 [SchedulerBinding.schedulerPhase] 的读取
/// 结果，让测试能模拟"_setControlsVisible 在 build 阶段被调用"的场景。
///
/// 生产代码不要触碰本字段。
@visibleForTesting
SchedulerPhase? debugSchedulerPhaseOverride;

/// 测试用类型别名——让单测拿 [GlobalKey<NiumaPlayerStateForTesting>] 后
/// 通过 `currentState` 访问 `@visibleForTesting` accessors，而不必把
/// 私有 [State] 类公开。
@visibleForTesting
typedef NiumaPlayerStateForTesting = _NiumaPlayerState;
