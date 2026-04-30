import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../observability/analytics_emitter.dart';
import '../orchestration/ad_schedule.dart';
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
      // 传空 list 而不是 DeviceOrientation.values：
      // - 空 list = 释放锁定，Android 回到 manifest screenOrientation
      //   设置（通常是 unspecified，跟设备传感器走）+ iOS 回到 plist
      //   UISupportedInterfaceOrientations。
      // - DeviceOrientation.values（含全 4 方向）会让 Android 解读
      //   成 SCREEN_ORIENTATION_FULL_USER 显式锁定，Activity 不再
      //   重新评估当前方向，用户感觉"无法旋转"。
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: NiumaFullscreenScope(
          child: NiumaPlayer(
            controller: widget.controller,
            adSchedule: widget.adSchedule,
            adAnalyticsEmitter: widget.adAnalyticsEmitter,
            pauseVideoDuringAd: widget.pauseVideoDuringAd,
            controlsAutoHideAfter: widget.controlsAutoHideAfter,
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

