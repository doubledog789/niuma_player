// 全屏路由页：复用同一个 controller，内部再放一个 StandardPlayer。
//
// 职责划分（见核里 web_fullscreen_coordination.dart 注释）：
// - io 平台：用 NiumaFullscreenController 在 initState/dispose 切朝向 +
//   SystemUI，竖屏视频锁竖屏、否则锁横屏。
// - web 平台：用 enterWebFullscreenRoute / exitWebFullscreenRoute 增减
//   进程级路由计数，并在内嵌播放器外包一层 NiumaFullscreenScope，让核里
//   的 NiumaPlayerView 把唯一的 <video> 元素搬到全屏这侧。
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

import 'standard_player.dart';

/// 全屏页。push 进来时进全屏，pop 时退全屏。
class FullscreenPage extends StatefulWidget {
  /// 构造全屏页。[controller] 与 inline 那份共用同一个实例；[title] 透传给顶栏。
  const FullscreenPage({
    super.key,
    required this.controller,
    required this.title,
  });

  /// 共用的播放 controller。
  final NiumaPlayerController controller;

  /// 顶栏标题。
  final String title;

  @override
  State<FullscreenPage> createState() => _FullscreenPageState();
}

class _FullscreenPageState extends State<FullscreenPage> {
  final NiumaFullscreenController _fs = NiumaFullscreenController();

  /// web：`fullscreenchange` 监听的反注册函数（处理用户按 ESC 退出真全屏）。
  void Function()? _fsUnsub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      enterWebFullscreenRoute();
      // 浏览器真全屏由 StandardPlayer 在用户手势栈内调起；这里只负责「用户按
      // ESC 退出浏览器全屏」时同步 pop 本路由，避免全屏页残留。
      _fsUnsub = onBrowserFullscreenChange((isFullscreen) {
        if (!isFullscreen && mounted) Navigator.of(context).maybePop();
      });
    } else {
      final size = widget.controller.value.size;
      _fs.enter(isVerticalVideo: size.height > size.width);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      _fsUnsub?.call();
      exitWebFullscreenRoute();
      exitBrowserFullscreen();
    } else {
      _fs.exit();
    }
    _fs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 全屏页里也用 StandardPlayer，inFullscreen:true 让它的全屏键变成 pop、
    // 不再 push，web 也不再重复包 scope。
    final player = StandardPlayer(
      controller: widget.controller,
      title: widget.title,
      inFullscreen: true,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        // web 上包一层 scope marker，让核里的 NiumaPlayerView 认出「这份在
        // 全屏路由内」，把单个 <video> 挂到这里。io 平台 scope 无副作用。
        child: kIsWeb ? NiumaFullscreenScope(child: player) : player,
      ),
    );
  }
}
