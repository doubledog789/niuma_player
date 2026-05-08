import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:niuma_player/niuma_player.dart';

import '_root_bg_io.dart' if (dart.library.html) '_root_bg_web.dart';

/// Web 全屏路由计数——有 N 个 [NiumaFullscreenPage] 处于活跃路由栈时为 N。
///
/// inline [NiumaPlayerView]（不在 [NiumaFullscreenScope] 子树里那一份）监听
/// 本计数：>0 时返 ColoredBox 不挂 HtmlElementView，让 wrapper `<video>`
/// 元素留在 fullscreen 那侧的 platform-view 容器里。
///
/// **必须用进程级计数而不是 backend 自家 ValueNotifier**：line failover 触发
/// backend swap 时新 backend 默认 `_isWebFullscreen=false`——inline 误判成
/// "已退出全屏"重新挂 HtmlElementView 抢回 wrapper，fullscreen 那边落空黑屏
/// （音频还在因为 video 元素本身没坏，只是被错误地搬到 inline 容器了）。
/// 进程级计数跟 [NiumaFullscreenPage] 路由生命周期挂钩，与 backend 实例
/// 解耦——backend 怎么换都不影响当前是否处于全屏。
///
/// io 平台不需要本计数（Texture / Surface 可以多处复用同一 textureId），
/// 但为简化代码 [NiumaPlayerView] 在所有平台都读这个值——非 web 平台
/// 永远 0，分支不命中。
final ValueNotifier<int> webFullscreenRouteCount = ValueNotifier<int>(0);

/// 公开只读视图——给 [NiumaPlayerView] 等下游 listener 用，不允许外部修改。
ValueListenable<int> get webFullscreenRouteCountListenable =>
    webFullscreenRouteCount;

/// 通过 [NiumaFullscreenPage.route] push 的全屏播放页。
///
/// 行为契约：
/// - **构造期**：锁定屏幕方向到 landscape（左 + 右），把 system UI 切到
///   `immersiveSticky`（隐藏状态栏与导航栏，用户从屏幕边缘滑入可短暂
///   唤回）。
/// - **dispose 期**：恢复 [DeviceOrientation.values]（解除方向锁）+
///   [SystemUiMode.edgeToEdge]（让内容继续画到 system bar 之下，
///   但 bar 自身可见）。
/// - **Web 平台**：[SystemChrome] 在 web 上是 no-op，但调用本身不会
///   抛——这里仍然显式用 [kIsWeb] 跳过，避免 console 噪音。
/// - **页面内容**：黑色 [Scaffold] + [SafeArea]（top/bottom = false，
///   让视频铺满，左右仍避开刘海）+ 内嵌一个 [NiumaPlayer]，与外部
///   page 用同一个 [NiumaPlayerController] 实例（不重新 initialize）。
///
/// 调用方仅通过 [NiumaFullscreenPage.route] 拿到 `Route<void>`，
/// `Navigator.push` 即进入全屏；`Navigator.pop` 即退出（[FullscreenButton]
/// 在子 route 上自动渲染 `fullscreen_exit` 图标并 pop）。
class NiumaFullscreenPage extends StatefulWidget {
  /// 构造一个 [NiumaFullscreenPage]。私有构造——使用方应通过
  /// [NiumaFullscreenPage.route] 拿到 [Route<void>] 后再 [Navigator.push]，
  /// 避免漏掉 page route 的 settings.name 与转场动画约定。
  const NiumaFullscreenPage._({
    required this.controller,
    this.theme,
    this.adSchedule,
    this.adAnalyticsEmitter,
    this.pauseVideoDuringAd = true,
    this.controlsAutoHideAfter = const Duration(seconds: 5),
    this.danmakuController,
    this.disabledGestures = const {},
    this.gestureHudBuilder,
    // M16 参数
    this.title,
    this.subtitle,
    this.controlBarConfig,
    this.fullscreenControlBarConfig = NiumaControlBarConfig.bili,
    this.buttonOverrides,
    this.bottomActionsBuilder,
    this.bottomTrailingBuilder,
    this.pausedOverlayBuilder,
    this.rightRailBuilder,
    this.moreMenuBuilder,
    this.chapters,
    this.onDanmakuInputTap,
    this.loadingBuilder,
    this.errorBuilder,
    this.endedBuilder,
    this.onErrorRetry,
    this.onEndedReplay,
  });

  /// 与外部 page 共享的 [NiumaPlayerController]。
  /// 进入 / 退出全屏不会重新 [NiumaPlayerController.initialize]，避免视频
  /// 中断。
  final NiumaPlayerController controller;

  /// 可选主题；为空则继承上层 [NiumaPlayerThemeData]，再为空则用默认值。
  final NiumaPlayerTheme? theme;

  /// 透传给内层 [NiumaPlayer] 的广告排期；为空则不渲染广告 overlay。
  final NiumaAdSchedule? adSchedule;

  /// 透传给内层 [NiumaPlayer] 的广告分析 emitter。
  final AnalyticsEmitter? adAnalyticsEmitter;

  /// 透传给内层 [NiumaPlayer] 的"广告显示期间是否暂停底层视频"。
  final bool pauseVideoDuringAd;

  /// 透传给内层 [NiumaPlayer] 的 auto-hide 时长。
  final Duration controlsAutoHideAfter;

  /// 透传给内层 [NiumaPlayer] 的弹幕 controller；为空则不渲染弹幕层。
  final NiumaDanmakuController? danmakuController;

  /// M13: 透传给内层 [NiumaPlayer] 的手势黑名单。
  final Set<GestureKind> disabledGestures;

  /// M13: 透传给内层 [NiumaPlayer] 的 HUD builder。
  final GestureHudBuilder? gestureHudBuilder;

  // ─── M16 参数 ───

  /// M16: 标题（透传给内层 [NiumaPlayer.title]）。
  final String? title;

  /// M16: 副标题（透传给内层 [NiumaPlayer.subtitle]）。
  final String? subtitle;

  /// M16: inline 控件条配置（透传给内层 [NiumaPlayer.controlBarConfig]）。
  final NiumaControlBarConfig? controlBarConfig;

  /// M16: 全屏控件条配置（透传给内层 [NiumaPlayer.fullscreenControlBarConfig]）。
  final NiumaControlBarConfig fullscreenControlBarConfig;

  /// M16: 按钮级覆盖（透传给内层 [NiumaPlayer.buttonOverrides]）。
  final Map<NiumaControlButton, ButtonOverride>? buttonOverrides;

  /// M16: 底栏额外 slot（透传给内层 [NiumaPlayer.bottomActionsBuilder]）。
  final WidgetBuilder? bottomActionsBuilder;

  /// M16: 底栏 trailing slot（透传给内层 [NiumaPlayer.bottomTrailingBuilder]）。
  final WidgetBuilder? bottomTrailingBuilder;

  /// M16: 暂停态 overlay（透传给内层 [NiumaPlayer.pausedOverlayBuilder]）。
  final WidgetBuilder? pausedOverlayBuilder;

  /// M16: 全屏右侧 rail（透传给内层 [NiumaPlayer.rightRailBuilder]）。
  final WidgetBuilder? rightRailBuilder;

  /// 透传给内层 [NiumaPlayer.loadingBuilder]——自定义 loading UI。
  final WidgetBuilder? loadingBuilder;

  /// 透传给内层 [NiumaPlayer.errorBuilder]——自定义错误 UI。
  final Widget Function(BuildContext, PlayerError)? errorBuilder;

  /// 透传给内层 [NiumaPlayer.endedBuilder]——自定义结束 UI。
  final WidgetBuilder? endedBuilder;

  /// 透传给内层 [NiumaPlayer.onErrorRetry]——默认错误 UI 的重试 callback。
  final VoidCallback? onErrorRetry;

  /// 透传给内层 [NiumaPlayer.onEndedReplay]——默认结束 UI 的重播 callback。
  final VoidCallback? onEndedReplay;

  /// M16: more menu builder（透传给内层 [NiumaPlayer.moreMenuBuilder]）。
  final List<PopupMenuEntry<dynamic>> Function(BuildContext)? moreMenuBuilder;

  /// M16: 视频章节（透传给内层 [NiumaPlayer.chapters]）。
  final List<Duration>? chapters;

  /// M16: 弹幕输入 tap 回调（透传给内层 [NiumaPlayer.onDanmakuInputTap]）。
  final VoidCallback? onDanmakuInputTap;

  /// page route 的 settings.name，保留作为子树反向识别的辅助手段；
  /// 但 `FullscreenButton` 现在主要通过内部的 InheritedWidget marker
  /// 判定（不再依赖 settings.name），避免子 route 嵌套时漏判 / 误判。
  static const String routeName = 'NiumaFullscreenPage';

  /// 创建一个 push 进全屏页的 [Route<void>]。
  ///
  /// 转场是 200ms 的淡入淡出（[PageRouteBuilder]），与 M9 主题
  /// `fadeInDuration` 默认值一致。
  ///
  /// [adSchedule] / [adAnalyticsEmitter] / [pauseVideoDuringAd] /
  /// [controlsAutoHideAfter] 全部透传给全屏页内的 [NiumaPlayer]——
  /// 不传时退化到 [NiumaPlayer] 的默认值，避免外层配置在跨页时丢失。
  static Route<void> route({
    required NiumaPlayerController controller,
    NiumaPlayerTheme? theme,
    NiumaAdSchedule? adSchedule,
    AnalyticsEmitter? adAnalyticsEmitter,
    bool pauseVideoDuringAd = true,
    Duration controlsAutoHideAfter = const Duration(seconds: 5),
    NiumaDanmakuController? danmakuController,
    Set<GestureKind> disabledGestures = const {},
    GestureHudBuilder? gestureHudBuilder,
    // M16 参数
    String? title,
    String? subtitle,
    NiumaControlBarConfig? controlBarConfig,
    NiumaControlBarConfig fullscreenControlBarConfig = NiumaControlBarConfig.bili,
    Map<NiumaControlButton, ButtonOverride>? buttonOverrides,
    WidgetBuilder? bottomActionsBuilder,
    WidgetBuilder? bottomTrailingBuilder,
    WidgetBuilder? pausedOverlayBuilder,
    WidgetBuilder? rightRailBuilder,
    WidgetBuilder? loadingBuilder,
    Widget Function(BuildContext, PlayerError)? errorBuilder,
    WidgetBuilder? endedBuilder,
    VoidCallback? onErrorRetry,
    VoidCallback? onEndedReplay,
    List<PopupMenuEntry<dynamic>> Function(BuildContext)? moreMenuBuilder,
    List<Duration>? chapters,
    VoidCallback? onDanmakuInputTap,
  }) {
    return PageRouteBuilder<void>(
      settings: const RouteSettings(name: routeName),
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => NiumaFullscreenPage._(
        controller: controller,
        theme: theme,
        adSchedule: adSchedule,
        adAnalyticsEmitter: adAnalyticsEmitter,
        pauseVideoDuringAd: pauseVideoDuringAd,
        controlsAutoHideAfter: controlsAutoHideAfter,
        danmakuController: danmakuController,
        disabledGestures: disabledGestures,
        gestureHudBuilder: gestureHudBuilder,
        title: title,
        subtitle: subtitle,
        controlBarConfig: controlBarConfig,
        fullscreenControlBarConfig: fullscreenControlBarConfig,
        buttonOverrides: buttonOverrides,
        bottomActionsBuilder: bottomActionsBuilder,
        bottomTrailingBuilder: bottomTrailingBuilder,
        pausedOverlayBuilder: pausedOverlayBuilder,
        rightRailBuilder: rightRailBuilder,
        loadingBuilder: loadingBuilder,
        errorBuilder: errorBuilder,
        endedBuilder: endedBuilder,
        onErrorRetry: onErrorRetry,
        onEndedReplay: onEndedReplay,
        moreMenuBuilder: moreMenuBuilder,
        chapters: chapters,
        onDanmakuInputTap: onDanmakuInputTap,
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  State<NiumaFullscreenPage> createState() => _NiumaFullscreenPageState();
}

/// InheritedWidget marker——出现在 [NiumaFullscreenPage] 子树中代表
/// "本 build context 处于全屏 page 内"。[FullscreenButton] 用
/// [maybeOf] 判定按钮该 push（进入全屏）还是 pop（退出全屏），
/// 不再依赖脆弱的 `route.isFirst` 兜底。
///
/// **不导出**：本类是 niuma_player 内部使用的 marker，不属于公开 API
/// （`lib/niuma_player.dart` 没 export）。用户不需要直接构造它；单测如
/// 需模拟"在 / 不在全屏页内"两种分支，可通过
/// `package:niuma_player/src/presentation/fullscreen/niuma_fullscreen_page.dart`
/// 的内部路径 import。
class NiumaFullscreenScope extends InheritedWidget {
  /// 构造一个 marker scope。
  const NiumaFullscreenScope({super.key, required super.child});

  /// 找最近的 [NiumaFullscreenScope]——存在即返回非空 marker。
  static NiumaFullscreenScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NiumaFullscreenScope>();
  }

  @override
  bool updateShouldNotify(NiumaFullscreenScope oldWidget) => false;
}

class _NiumaFullscreenPageState extends State<NiumaFullscreenPage> {
  /// Web 上记录 enter 时的播放状态——dispose 时若 video 因 wrapper move
  /// 短暂孤立被浏览器暂停，恢复 inline 时显式调一次 play() 续播。
  bool _wasPlayingOnEnter = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      // 按视频自然比例选锁定方向：
      // - 竖直视频 (height > width，如 9:16 短视频) → 锁竖屏，避免被
      //   landscape 强行旋成左右黑边窄缝
      // - 横屏 / 未知 → 锁横屏（长视频默认）
      //
      // size 在 onLoadedMetadata 之后才有值；用户点全屏前一般视频已经
      // 加载好。元数据未到 / 未 init 时退到 landscape 默认，安全又不会
      // 误把横屏视频锁成竖屏。
      final size = widget.controller.value.size;
      final isVerticalVideo = size.width > 0 &&
          size.height > 0 &&
          size.height > size.width;
      if (isVerticalVideo) {
        SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
          DeviceOrientation.portraitUp,
        ]);
      } else {
        SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      // Web 流程关键设计：
      //
      // 1. 用 [WidgetsBinding.addPostFrameCallback] 把 counter++ 推迟到第一
      //    帧之后——本次 build 期 inline 仍在挂 HtmlElementView（counter=0）、
      //    fullscreen 这侧也在挂 HtmlElementView（counter=0 但
      //    inFullscreenRoute=true 不影响），两侧 factory 同时被调，wrapper
      //    通过第二次 mount 的 `appendChild` **原子搬**到 fullscreen 容器
      //    （DOM appendChild 把 element 从旧 parent 移到新 parent 是 atomic
      //    操作，video 不经过 orphan）。Frame commit 后 postFrame 触发
      //    counter++ → inline 重建为 ColoredBox（HtmlElementView 卸下，
      //    容器移除，但里面已经空——wrapper 早搬走了）。
      //
      //    若 counter++ 同步在这里，fsState=true 立刻 fire，inline 第一时间
      //    rebuild 为 ColoredBox **先把 inline 容器拆掉**，wrapper 跟着被
      //    DOM tree cascade orphan，再被 fullscreen 重新 attach——orphan
      //    瞬间触发浏览器暂停 video。
      //
      // 2. 记录 enter 时的播放状态，dispose 时如有需要 fallback play()——
      //    exit 路径上 unmount/mount 顺序是 Flutter 内部决定的，可能 inline
      //    重 mount 之前 fullscreen 容器已经先被 dispose 移除一次，wrapper
      //    短暂 orphan 还是会被浏览器暂停。
      _wasPlayingOnEnter =
          widget.controller.value.phase == PlayerPhase.playing;
      // PWA 模式 iOS Safari 全屏后 viewport 与视频 aspect ratio 错位，
      // host 页面默认白底会从空地露出来——很突兀。进 fullscreen route
      // 把 <body> / <html> 背景刷黑，dispose 时还原。io 平台是 no-op。
      setWebRootBackground('#000');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        webFullscreenRouteCount.value = webFullscreenRouteCount.value + 1;
        // 兜底：理论上 atomic appendChild move 不会 pause video，但
        // iOS Safari 在某些 build 阶段 reflow 时仍可能让 video 短暂卡住。
        // enter 时如果原来是 playing，再下一帧（counter 翻完 inline 已重建
        // 为 ColoredBox）显式 play() 一次，确保续播。
        if (_wasPlayingOnEnter) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (widget.controller.value.phase != PlayerPhase.playing) {
              widget.controller.play();
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      // Android 退全屏方向恢复需要两步走：
      //
      // 1) 先显式设 [portraitUp]——给 Activity 一个"竖屏"信号触发
      //    onConfigurationChanged，Android 把当前 surface 从横屏切回
      //    竖屏。如果不做这一步，仅传空 list 解锁，Activity 仍停在
      //    横屏 config 直到用户物理旋转设备，用户体感"退出全屏没回正"。
      // 2) 下一帧再传空 list 释放锁定，让用户后续能按设备传感器自由
      //    旋转（不强制竖屏锁定）。
      //
      // iOS 不走 step 1：host app 的 `Info.plist` 若只声明 landscape
      // supported（短视频/视频类常见），portrait 请求会撞 UISceneError
      // "None of the requested orientations are supported"——纯日志噪音
      // 但用户看着烦。SystemChrome 在 iOS 上传空 list 立刻生效，单步够用。
      if (defaultTargetPlatform == TargetPlatform.android) {
        SystemChrome.setPreferredOrientations(
          const <DeviceOrientation>[DeviceOrientation.portraitUp],
        );
        SchedulerBinding.instance.addPostFrameCallback((_) {
          SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
        });
      } else {
        SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      // 退全屏路径：counter--，inline 重新挂 HtmlElementView，wrapper
      // 在 inline 与 fullscreen 容器之间 move 回 inline。enter 时 video
      // 处于 playing 的话，schedule 一次 play() 兜底——以防 unmount/mount
      // 顺序导致 wrapper 短暂 orphan 触发浏览器暂停。
      if (webFullscreenRouteCount.value > 0) {
        webFullscreenRouteCount.value =
            webFullscreenRouteCount.value - 1;
      }
      // 退出 fullscreen route 还原 root 背景——传 null 清空 inline style，
      // 回到 host 页面自家 CSS 设定的默认值。
      setWebRootBackground(null);
      if (_wasPlayingOnEnter) {
        Future.microtask(() {
          if (widget.controller.value.phase != PlayerPhase.playing) {
            widget.controller.play();
          }
        });
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      top: false,
      bottom: kIsWeb,
      left: false,
      right: false,
      child: NiumaFullscreenScope(
        child: NiumaPlayer(
            controller: widget.controller,
            adSchedule: widget.adSchedule,
            adAnalyticsEmitter: widget.adAnalyticsEmitter,
            pauseVideoDuringAd: widget.pauseVideoDuringAd,
            controlsAutoHideAfter: widget.controlsAutoHideAfter,
            danmakuController: widget.danmakuController,
            gesturesEnabledInline: false,
            disabledGestures: widget.disabledGestures,
            gestureHudBuilder: widget.gestureHudBuilder,
            // M16 参数：全屏页内 NiumaPlayer 检测到 NiumaFullscreenScope 后
            // 渲染 NiumaFullscreenControlBar，这些参数才真正生效。
            title: widget.title,
            subtitle: widget.subtitle,
            controlBarConfig: widget.controlBarConfig,
            fullscreenControlBarConfig: widget.fullscreenControlBarConfig,
            buttonOverrides: widget.buttonOverrides,
            bottomActionsBuilder: widget.bottomActionsBuilder,
            bottomTrailingBuilder: widget.bottomTrailingBuilder,
            pausedOverlayBuilder: widget.pausedOverlayBuilder,
            rightRailBuilder: widget.rightRailBuilder,
            loadingBuilder: widget.loadingBuilder,
            errorBuilder: widget.errorBuilder,
            endedBuilder: widget.endedBuilder,
            onErrorRetry: widget.onErrorRetry,
            onEndedReplay: widget.onEndedReplay,
            moreMenuBuilder: widget.moreMenuBuilder,
            chapters: widget.chapters,
            onDanmakuInputTap: widget.onDanmakuInputTap,
          ),
        ),
      );
    final scaffold = Scaffold(
      backgroundColor: Colors.black,
      // SafeArea 全关——横屏全屏 immersiveSticky 模式系统 bar 已隐藏，
      // 默认左右 inset 会把 NiumaPlayer 推离屏幕边缘 24-48px（Android
      // 曲面屏 / cutout），导致顶栏 ⋮ / 底栏元素永远贴不到屏幕真正边缘。
      //
      // Web 例外：[SystemChrome] 在 web 上是 no-op，PWA 模式 iOS Safari
      // 不旋转屏幕的"竖屏全屏"下方 home indicator 区域仍会盖住底部
      // 控件条——给 bottom 留 inset。viewport-fit=cover 没设的话
      // MediaQuery.padding.bottom=0，SafeArea 自然 no-op，不影响其它情况。
      body: kIsWeb
          ? Stack(
              children: [
                Positioned.fill(child: body),
                // Web 端旋转提示——竖屏时浮在顶部居中，5s 自动消失，
                // 旋转到横屏立刻隐藏。SystemChrome.setPreferredOrientations
                // 在 web 上是 no-op、无法程序化锁横屏，靠用户手动旋转设备
                // 才能拿到 bili 风全屏的最佳视觉。
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Center(
                      child: _WebRotationHint(
                        controller: widget.controller,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : body,
    );
    if (widget.theme != null) {
      return NiumaPlayerThemeData(data: widget.theme!, child: scaffold);
    }
    return scaffold;
  }
}

/// Web 端竖屏全屏时浮在顶部的"请旋转屏幕"提示。
///
/// 显示规则：
/// - 仅 web 平台调用本 widget；io 平台不挂；
/// - 视频是**横屏视频**才显示（竖直视频在竖屏里已经是最佳画布，旋转无益）；
///   未 init / size 未知时也不显示；
/// - 当前 [Orientation.portrait] 才渲染，[Orientation.landscape] 即时
///   收起（旋转后立刻消失，不需要等 timer）；
/// - 5s 后自动 fade out（即使用户没旋转），不再持续打扰；
/// - 用户点击 hint 提前关闭。
///
/// 复显规则：用户已经看过一次（timer 跑完或主动点关）后，本 widget 实例
/// 就不再显示。route pop 后下次再 push 全屏会重新挂一个新实例，重新计时。
class _WebRotationHint extends StatefulWidget {
  const _WebRotationHint({required this.controller});

  final NiumaPlayerController controller;

  @override
  State<_WebRotationHint> createState() => _WebRotationHintState();
}

class _WebRotationHintState extends State<_WebRotationHint> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (!_visible) return;
    _timer?.cancel();
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return ValueListenableBuilder<NiumaPlayerValue>(
      valueListenable: widget.controller,
      builder: (ctx, value, _) {
        final size = value.size;
        // size 未 init 不显示——视频比例未知不能误导用户旋转。
        if (size.width <= 0 || size.height <= 0) {
          return const SizedBox.shrink();
        }
        // 竖直视频不显示——竖屏播竖直视频已经是最佳画布，旋转反而会
        // 把视频压成中间一条窄缝。
        if (size.height > size.width) {
          return const SizedBox.shrink();
        }
        return OrientationBuilder(
          builder: (ctx, orientation) {
            // 横屏时不显示——用户已经在最佳视角了。
            if (orientation == Orientation.landscape) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AnimatedOpacity(
                opacity: _visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: GestureDetector(
                  onTap: _dismiss,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.screen_rotation,
                          color: Colors.white,
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          '旋转屏幕获得更好观看体验',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

