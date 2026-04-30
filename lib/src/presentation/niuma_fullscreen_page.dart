import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  });

  /// 与外部 page 共享的 [NiumaPlayerController]。
  /// 进入 / 退出全屏不会重新 [NiumaPlayerController.initialize]，避免视频
  /// 中断。
  final NiumaPlayerController controller;

  /// 可选主题；为空则继承上层 [NiumaPlayerThemeData]，再为空则用默认值。
  final NiumaPlayerTheme? theme;

  /// page route 的 settings.name，用于在 widget tree 内反向识别"我是否
  /// 在全屏 page 内"——目前 [FullscreenButton] 用 `ModalRoute.of(...)
  /// .isFirst` 做判定，这个常量预留给以后更精细的判定。
  static const String routeName = 'NiumaFullscreenPage';

  /// 创建一个 push 进全屏页的 [Route<void>]。
  ///
  /// 转场是 200ms 的淡入淡出（[PageRouteBuilder]），与 M9 主题
  /// `fadeInDuration` 默认值一致。
  static Route<void> route({
    required NiumaPlayerController controller,
    NiumaPlayerTheme? theme,
  }) {
    return PageRouteBuilder<void>(
      settings: const RouteSettings(name: routeName),
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => NiumaFullscreenPage._(
        controller: controller,
        theme: theme,
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  State<NiumaFullscreenPage> createState() => _NiumaFullscreenPageState();
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
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
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
        child: NiumaPlayer(controller: widget.controller),
      ),
    );
    if (widget.theme != null) {
      return NiumaPlayerThemeData(data: widget.theme!, child: scaffold);
    }
    return scaffold;
  }
}

