import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../domain/gesture_kind.dart';
import '../observability/analytics_emitter.dart';
import 'ad_schedule.dart';
import 'button_override.dart';
import 'niuma_control_bar_config.dart';
import 'niuma_control_button.dart';
import 'niuma_danmaku_controller.dart';
import 'niuma_gesture_layer.dart' show GestureHudBuilder;
import 'niuma_player.dart';
import 'niuma_player_controller.dart';
import 'niuma_player_theme.dart';

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
/// `package:niuma_player/src/presentation/niuma_fullscreen_page.dart`
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
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: Colors.black,
      // SafeArea 全关——横屏全屏 immersiveSticky 模式系统 bar 已隐藏，
      // 默认左右 inset 会把 NiumaPlayer 推离屏幕边缘 24-48px（Android
      // 曲面屏 / cutout），导致顶栏 ⋮ / 底栏元素永远贴不到屏幕真正边缘。
      body: SafeArea(
        top: false,
        bottom: false,
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
            // 渲染 BiliStyleControlBar，这些参数才真正生效。
            title: widget.title,
            subtitle: widget.subtitle,
            controlBarConfig: widget.controlBarConfig,
            fullscreenControlBarConfig: widget.fullscreenControlBarConfig,
            buttonOverrides: widget.buttonOverrides,
            bottomActionsBuilder: widget.bottomActionsBuilder,
            bottomTrailingBuilder: widget.bottomTrailingBuilder,
            pausedOverlayBuilder: widget.pausedOverlayBuilder,
            rightRailBuilder: widget.rightRailBuilder,
            moreMenuBuilder: widget.moreMenuBuilder,
            chapters: widget.chapters,
            onDanmakuInputTap: widget.onDanmakuInputTap,
          ),
        ),
      ),
    );
    if (widget.theme != null) {
      return NiumaPlayerThemeData(data: widget.theme!, child: scaffold);
    }
    return scaffold;
  }
}

