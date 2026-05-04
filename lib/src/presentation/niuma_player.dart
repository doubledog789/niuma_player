import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../cast/cast_device.dart';
import '../cast/cast_registry.dart';
import '../domain/gesture_kind.dart';
import '../domain/player_state.dart';
import '../observability/analytics_emitter.dart';
import '../orchestration/ad_schedule.dart';
import '../orchestration/ad_scheduler.dart';
import 'bili_style_control_bar.dart';
import 'button_override.dart';
import 'cast/niuma_cast_button.dart';
import 'cast/niuma_cast_overlay.dart';
import 'cast/niuma_cast_picker_panel.dart';
import 'controls/pip_button.dart';
import 'niuma_ad_overlay.dart';
import 'niuma_control_bar.dart';
import 'niuma_control_bar_config.dart';
import 'niuma_control_button.dart';
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
    // M16：配置驱动 UI / 全屏 swap / cast picker panel
    this.title,
    this.subtitle,
    this.controlBarConfig,
    this.fullscreenControlBarConfig = NiumaControlBarConfig.bili,
    this.buttonOverrides,
    this.bottomActionsBuilder,
    this.bottomTrailingBuilder,
    this.rightRailBuilder,
    this.moreMenuBuilder,
    this.chapters,
    this.onDanmakuInputTap,
    this.actionsBuilder,
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

  // ───────────────── M16 配置驱动 UI ─────────────────

  /// 标题（在全屏顶栏 [NiumaControlButton.title] 的 [TitleBar] 渲染）；
  /// inline 状态默认走 _LegacyM9Bar 不展示标题。
  final String? title;

  /// 副标题（同 [title]）。
  final String? subtitle;

  /// inline 控件条配置：
  /// - `null`（默认）：[NiumaControlBar] 走 M9 9 按钮老逻辑，向后兼容。
  /// - 非 null：把 enum list 透传给 [NiumaControlBar] 走配置驱动渲染。
  final NiumaControlBarConfig? controlBarConfig;

  /// 全屏控件条配置（[BiliStyleControlBar]）。默认 [NiumaControlBarConfig.bili]。
  final NiumaControlBarConfig fullscreenControlBarConfig;

  /// 按钮级覆盖：把指定 enum 的默认 widget 替换为业务自定义内容。
  /// 仅在全屏 [BiliStyleControlBar] 上生效（inline 暂不支持）。
  final Map<NiumaControlButton, ButtonOverride>? buttonOverrides;

  /// 底栏左侧按钮区**之后**的额外 slot——业务想塞 next/prev 等"接 playPause"
  /// 的播放列表按钮就放这里。仅全屏生效。
  final WidgetBuilder? bottomActionsBuilder;

  /// 底栏右侧 enum **之前**的额外 slot——业务想把"选集 / 集数"等放在
  /// 倍速 / 线路切换 之前就放这里。仅全屏生效。
  final WidgetBuilder? bottomTrailingBuilder;

  /// 全屏右侧 rail（垂直堆叠的浮动按钮，B 站风格"点赞 / 投币 / 收藏 / 分享"）。
  final WidgetBuilder? rightRailBuilder;

  /// 全屏 [NiumaControlButton.more] 弹出 PopupMenu 的 builder——返回 entries
  /// list 由 [showMenu] 渲染。
  final List<PopupMenuEntry<dynamic>> Function(BuildContext)? moreMenuBuilder;

  /// 视频章节起点位置（透到 [ScrubBar.chapters]，全屏 BiliStyleControlBar
  /// 进度条会画刻度）。
  final List<Duration>? chapters;

  /// 全屏 [DanmakuInputPill] tap 回调——业务弹自家 input bottom sheet 用。
  final VoidCallback? onDanmakuInputTap;

  /// 全屏顶栏 topActions enum 之后追加的业务自定义 slot
  /// （业务互动按钮如点赞 / 分享等）。仅全屏 [BiliStyleControlBar] 生效。
  final WidgetBuilder? actionsBuilder;

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

  // ───────────── M16 cast picker panel state ─────────────

  /// cast picker panel 是否当前可见。
  bool _showCastPicker = false;

  /// 弹出 panel 那一刻播放器是否在 playing——关闭 panel 时按这个决定是否
  /// 自动恢复 play。
  bool _wasPlayingBeforeCast = false;

  /// 已发现的 cast devices（去重）。
  final List<CastDevice> _castDevices = <CastDevice>[];

  /// 当前是否在扫描 cast devices。
  bool _isCastScanning = false;

  /// 扫描产生的 [Stream] 订阅，dispose 时取消。
  final List<StreamSubscription<List<CastDevice>>> _castScanSubs =
      <StreamSubscription<List<CastDevice>>>[];

  /// 扫描超时计时器（8s 兜底，防止无限扫描）。
  Timer? _castScanTimeout;

  /// 当前还在扫描的协议数。降到 0 时停止 scanning 状态。
  int _castScanPendingSubs = 0;

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
    _cancelCastScan();
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

  // ───────────── M16 cast picker panel methods ─────────────

  /// 弹出 cast picker：记录当前 isPlaying，pause 视频，开始扫描设备。
  void _openCastPicker() {
    if (_showCastPicker) return;
    setState(() {
      _wasPlayingBeforeCast = widget.controller.value.isPlaying;
      _showCastPicker = true;
      _castDevices.clear();
    });
    // pause 走 fire-and-forget——业务侧实现可能是 async。Tests 里 fake
    // controller 同步落地，prod controller 也只是发个 platform call，
    // 我们不必 await。
    unawaited(widget.controller.pause());
    _startCastScan();
  }

  /// 关闭 cast picker：隐藏 panel + 取消扫描；如果弹出前在 playing，
  /// 恢复 play。
  void _closeCastPicker() {
    if (!_showCastPicker) return;
    setState(() {
      _showCastPicker = false;
      _isCastScanning = false;
    });
    _cancelCastScan();
    if (_wasPlayingBeforeCast) {
      unawaited(widget.controller.play());
    }
  }

  /// 启动 / 重启 cast 设备扫描（8s 兜底）。
  void _startCastScan() {
    _cancelCastScan();
    final services = NiumaCastRegistry.all();
    setState(() {
      _isCastScanning = true;
      _castScanPendingSubs = services.length;
      _castDevices.clear();
    });
    if (services.isEmpty) {
      // 没注册任何 protocol——直接停止 scanning 状态。
      setState(() => _isCastScanning = false);
      return;
    }
    for (final svc in services) {
      _castScanSubs.add(svc.discover().listen(
            (batch) {
              if (!mounted) return;
              setState(() {
                for (final d in batch) {
                  if (!_castDevices.any((e) => e.id == d.id)) {
                    _castDevices.add(d);
                  }
                }
              });
            },
            onDone: _onCastScanSubDone,
            onError: (_) => _onCastScanSubDone(),
          ));
    }
    _castScanTimeout = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      if (_isCastScanning) {
        setState(() => _isCastScanning = false);
      }
    });
  }

  /// 一条协议扫描结束（done / error）时减计数；归零时清 scanning 标志。
  void _onCastScanSubDone() {
    // _cancelCastScan 会把 _castScanPendingSubs 清零，此后仍可能有
    // stream onDone 延迟回调——加 guard 避免 underflow 到 -1。
    if (_castScanPendingSubs <= 0) return;
    _castScanPendingSubs--;
    if (_castScanPendingSubs <= 0) {
      _castScanTimeout?.cancel();
      _castScanTimeout = null;
      if (!mounted) return;
      setState(() => _isCastScanning = false);
    }
  }

  void _cancelCastScan() {
    for (final s in _castScanSubs) {
      unawaited(s.cancel());
    }
    _castScanSubs.clear();
    _castScanTimeout?.cancel();
    _castScanTimeout = null;
    _castScanPendingSubs = 0;
  }

  /// 选定 cast 设备：连接对应 protocol 的 service，把 session 推给
  /// controller，关 panel。出错时弹 toast 并保持 panel。
  Future<void> _onSelectCastDevice(CastDevice device) async {
    final svc = NiumaCastRegistry.byProtocolId(device.protocolId);
    if (svc == null) return;
    // 先关 panel——用户体感"点了就关"；连接异步进行。
    setState(() => _showCastPicker = false);
    _cancelCastScan();
    try {
      final session = await svc.connect(device, widget.controller);
      // controller.connectCast 会自己 pause 本地 backend 并 emit CastStarted。
      await widget.controller.connectCast(session);
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(content: Text('连接失败：$e')));
    }
  }

  /// 全屏 [BiliStyleControlBar] 的 onMore 回调——内置「投屏」「画中画」
  /// 两项，之后追加业务侧 [moreMenuBuilder] 返回的条目（用分隔线隔开）。
  void _showMoreMenu(BuildContext ctx) {
    final extra = widget.moreMenuBuilder?.call(ctx) ?? <PopupMenuEntry<dynamic>>[];
    // ctx 是 NiumaPlayer 整体 BuildContext，而不是 ⋮ 按钮——之前用
    // ctx.findRenderObject() 算 popup 位置会锚到 player 左上角，导致
    // 用户看到"菜单弹到左边"。改用屏幕宽度算右上锚位，让 popup 从
    // 顶栏下方右侧弹出，视觉上跟随 ⋮ 按钮位置。
    final size = MediaQuery.of(ctx).size;
    final position = RelativeRect.fromLTRB(
      size.width - 200, // popup 右上角离屏左 (size.width - 200)
      60, // 顶栏高度 ~50，60 让 popup 在顶栏下方
      8, // popup 离屏幕右 8px
      0,
    );
    showMenu<dynamic>(
      context: ctx,
      position: position,
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem<dynamic>(
          value: '__niuma_cast',
          child: Row(
            children: const [
              Icon(Icons.cast, size: 18),
              SizedBox(width: 8),
              Text('投屏'),
            ],
          ),
        ),
        PopupMenuItem<dynamic>(
          value: '__niuma_pip',
          child: Row(
            children: const [
              Icon(Icons.picture_in_picture_alt, size: 18),
              SizedBox(width: 8),
              Text('画中画'),
            ],
          ),
        ),
        if (extra.isNotEmpty) const PopupMenuDivider(),
        ...extra,
      ],
    ).then((value) {
      if (value == '__niuma_cast') _openCastPicker();
      if (value == '__niuma_pip') _enterPip();
    });
  }

  /// 退出全屏：当前在 [NiumaFullscreenScope] 里时 pop route；否则 no-op。
  void _exitFullscreen(BuildContext ctx) {
    final nav = Navigator.maybeOf(ctx);
    if (nav != null && nav.canPop()) nav.pop();
  }

  /// 进入 PiP：直接代到 controller。失败静默忽略。
  void _enterPip() {
    unawaited(widget.controller.enterPictureInPicture());
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

  /// 测试用：当前 `_showCastPicker` 字段值。
  @visibleForTesting
  bool get debugShowCastPicker => _showCastPicker;

  /// 测试用：当前 `_wasPlayingBeforeCast` 字段值。
  @visibleForTesting
  bool get debugWasPlayingBeforeCast => _wasPlayingBeforeCast;

  /// 测试用：直接调 [_openCastPicker]。
  @visibleForTesting
  void debugOpenCastPicker() => _openCastPicker();

  /// 测试用：直接调 [_closeCastPicker]。
  @visibleForTesting
  void debugCloseCastPicker() => _closeCastPicker();

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
        // M16：全屏（NiumaFullscreenScope 注入）走 BiliStyleControlBar，
        // inline 走原 NiumaControlBar——同一棵树，按当前 BuildContext
        // 是否在 fullscreen scope 里 swap。
        final isFullscreen =
            NiumaFullscreenScope.maybeOf(innerContext) != null;

        // 全屏底栏：BiliStyleControlBar 自带 top + bottom + center + rail，
        // 替代 inline 模式下的 [NiumaCastButton + PipButton] 右上 actions
        // 区（这两个按钮在全屏的 topActions enum 里有重渲染入口）。
        // inline：保留 M9 行为——NiumaControlBar 在底部 + 右上 Cast/PiP 浮层。
        final controlBarLayer = isFullscreen
            ? BiliStyleControlBar(
                controller: widget.controller,
                config: widget.fullscreenControlBarConfig,
                title: widget.title,
                subtitle: widget.subtitle,
                chapters: widget.chapters,
                controlsVisible: _controlsVisible,
                buttonOverrides: widget.buttonOverrides,
                actionsBuilder: widget.actionsBuilder,
                bottomActionsBuilder: widget.bottomActionsBuilder,
                bottomTrailingBuilder: widget.bottomTrailingBuilder,
                rightRailBuilder: widget.rightRailBuilder,
                onBack: () => _exitFullscreen(innerContext),
                onCast: _openCastPicker,
                onPip: _enterPip,
                onMore: () => _showMoreMenu(innerContext),
                onDanmakuInputTap: widget.onDanmakuInputTap,
              )
            : NiumaControlBar(
                controller: widget.controller,
                config: widget.controlBarConfig,
              );

        // PiP 模式下整个浮层组（手势层 / 弹幕 / 控件条 / PipButton / 广告）
        // 隐藏，只剩裸 NiumaPlayerView——
        //   1. 行为契合"画中画窗只放画面"的产品语义；
        //   2. Android PiP 把 Activity 缩到极小尺寸时 NiumaControlBar 的
        //      Row（8 按钮+Spacer）会 RenderFlex overflow，藏掉就不报错。
        // 用 ValueListenableBuilder 的 child 优化：浮层 Stack 只 build 一次，
        // builder 仅在 PiP 状态翻转时切 child↔SizedBox，避免每帧都重建浮层。
        final overlays = Stack(
          fit: StackFit.expand,
          children: [
            // M15: 投屏覆盖层——视频之上最底层浮层，投屏中显示设备信息。
            Positioned.fill(
              child: NiumaCastOverlay(controller: widget.controller),
            ),
            // 手势层：放在视频之上、控件之下。
            // M9 既有"单击切控件显隐"行为通过 onTap: _onTapVideo 透传保留。
            // enabled：全屏 scope 内永远 true；inline 场景看 gesturesEnabledInline。
            Positioned.fill(
              child: NiumaGestureLayer(
                controller: widget.controller,
                enabled: isFullscreen || widget.gesturesEnabledInline,
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
            // 全屏：BiliStyleControlBar 用 Stack/Positioned 自己排 top/bottom/
            // center/rail，必须铺满整个浮层 Stack——把它放在独立的
            // Positioned.fill 槽里。inline：保留 M9 老行为，Align bottom。
            if (isFullscreen)
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: fadeDuration,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: controlBarLayer,
                  ),
                ),
              )
            else
              AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: fadeDuration,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: controlBarLayer,
                  ),
                ),
              ),
            // M12: 右上角 PipButton + Cast 浮层（仅 inline；全屏的 Cast/PiP
            // 在 BiliStyleControlBar 的 topActions 里走 enum 渲染）。
            if (!isFullscreen)
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
                        // 右上 actions 区——投屏 + PiP 集中放这里，跟主流
                        // 播放器的"top-right action bar"惯例一致，不再挤
                        // 底部 ControlBar。
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            NiumaCastButton(controller: widget.controller, onTap: _openCastPicker),
                            PipButton(controller: widget.controller),
                          ],
                        ),
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
            // M16: cast picker panel——铺整个 player，左暗 + 右设备列表。
            // 放在 ad overlay 之上，cast picker 时屏蔽广告。
            if (_showCastPicker)
              Positioned.fill(
                child: NiumaCastPickerPanel(
                  controller: widget.controller,
                  onClose: _closeCastPicker,
                  devices: _castDevices,
                  isScanning: _isCastScanning,
                  onSelectDevice: _onSelectCastDevice,
                  onRefresh: _startCastScan,
                ),
              ),
          ],
        );

        return Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: (_) => _onUserActivity(),
          onPointerMove: (_) => _onUserActivity(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NiumaPlayerView(widget.controller),
              ValueListenableBuilder<NiumaPlayerValue>(
                valueListenable: widget.controller,
                child: overlays,
                builder: (ctx, v, child) =>
                    v.isInPictureInPicture ? const SizedBox.shrink() : child!,
              ),
            ],
          ),
        );
      },
    );

    // 包一层 NiumaPlayerConfigScope，让子树（特别是 FullscreenButton）
    // 在 push 全屏 route 时能读到外层 NiumaPlayer 的全部配置——避免
    // 全屏页内部的 NiumaPlayer 丢失 adSchedule / theme / autoHide 等
    // 关键 props。M16 新增 9 个参数同样透传，让全屏页里的 NiumaPlayer
    // 能正确渲染 BiliStyleControlBar 配置。
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
      // M16 参数
      title: widget.title,
      subtitle: widget.subtitle,
      controlBarConfig: widget.controlBarConfig,
      fullscreenControlBarConfig: widget.fullscreenControlBarConfig,
      buttonOverrides: widget.buttonOverrides,
      bottomActionsBuilder: widget.bottomActionsBuilder,
      bottomTrailingBuilder: widget.bottomTrailingBuilder,
      rightRailBuilder: widget.rightRailBuilder,
      moreMenuBuilder: widget.moreMenuBuilder,
      chapters: widget.chapters,
      onDanmakuInputTap: widget.onDanmakuInputTap,
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
    // M16 参数
    required this.title,
    required this.subtitle,
    required this.controlBarConfig,
    required this.fullscreenControlBarConfig,
    required this.buttonOverrides,
    required this.bottomActionsBuilder,
    required this.bottomTrailingBuilder,
    required this.rightRailBuilder,
    required this.moreMenuBuilder,
    required this.chapters,
    required this.onDanmakuInputTap,
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

  // ─── M16 参数 ───

  /// M16: 标题（透传给全屏页 NiumaPlayer.title）。
  final String? title;

  /// M16: 副标题（透传给全屏页 NiumaPlayer.subtitle）。
  final String? subtitle;

  /// M16: inline 控件条配置（透传给全屏页 NiumaPlayer.controlBarConfig）。
  final NiumaControlBarConfig? controlBarConfig;

  /// M16: 全屏控件条配置（透传给全屏页 NiumaPlayer.fullscreenControlBarConfig）。
  final NiumaControlBarConfig fullscreenControlBarConfig;

  /// M16: 按钮级覆盖（透传给全屏页 NiumaPlayer.buttonOverrides）。
  final Map<NiumaControlButton, ButtonOverride>? buttonOverrides;

  /// M16: 底栏额外 slot（透传给全屏页 NiumaPlayer.bottomActionsBuilder）。
  final WidgetBuilder? bottomActionsBuilder;

  /// M16: 底栏 trailing slot（透传给全屏页 NiumaPlayer.bottomTrailingBuilder）。
  final WidgetBuilder? bottomTrailingBuilder;

  /// M16: 全屏右侧 rail（透传给全屏页 NiumaPlayer.rightRailBuilder）。
  final WidgetBuilder? rightRailBuilder;

  /// M16: more menu builder（透传给全屏页 NiumaPlayer.moreMenuBuilder）。
  final List<PopupMenuEntry<dynamic>> Function(BuildContext)? moreMenuBuilder;

  /// M16: 视频章节（透传给全屏页 NiumaPlayer.chapters）。
  final List<Duration>? chapters;

  /// M16: 弹幕输入 tap 回调（透传给全屏页 NiumaPlayer.onDanmakuInputTap）。
  final VoidCallback? onDanmakuInputTap;

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
      oldWidget.gesturesEnabledInline != gesturesEnabledInline ||
      title != oldWidget.title ||
      subtitle != oldWidget.subtitle ||
      controlBarConfig != oldWidget.controlBarConfig ||
      fullscreenControlBarConfig != oldWidget.fullscreenControlBarConfig ||
      buttonOverrides != oldWidget.buttonOverrides ||
      bottomActionsBuilder != oldWidget.bottomActionsBuilder ||
      bottomTrailingBuilder != oldWidget.bottomTrailingBuilder ||
      rightRailBuilder != oldWidget.rightRailBuilder ||
      moreMenuBuilder != oldWidget.moreMenuBuilder ||
      chapters != oldWidget.chapters ||
      onDanmakuInputTap != oldWidget.onDanmakuInputTap;
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

/// 测试用别名——指向 [NiumaFullscreenScope]，让单测能在不引内部路径的情况下
/// 包一层 fullscreen marker，触发 NiumaPlayer 的 BiliStyleControlBar swap。
@visibleForTesting
typedef NiumaFullscreenScopeForTesting = NiumaFullscreenScope;

/// 测试用别名——指向 [BiliStyleControlBar] 类型，单测 `find.byType` 用。
@visibleForTesting
typedef BiliStyleControlBarTypeForTesting = BiliStyleControlBar;

/// 测试用别名——指向 [NiumaCastPickerPanel] 类型，单测 `find.byType` 用。
@visibleForTesting
typedef NiumaCastPickerPanelTypeForTesting = NiumaCastPickerPanel;
