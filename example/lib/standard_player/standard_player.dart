// 标准播放器 UI 接入范式。
//
// 这是接入方（和 AI）照着扩的模板：用一个 ValueListenableBuilder 监听
// headless 核的 NiumaPlayerValue，Stack 从下到上分层叠：
//   画面 → 封面 → 手势 → loading → 错误 → 结束 → 控件（顶栏/底栏）。
// 顶栏底栏共用一个可见性开关 + 3s 自动隐藏；手势透传给 NiumaGestureController；
// 全屏 push 一个 FullscreenPage 复用同一 controller。
//
// 换皮只需改各子层 widget，业务逻辑都在核里——controller 驱动播放，
// gesture controller 处理手势意图，fullscreen controller 处理朝向/SystemUI。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

import 'controls.dart';
import 'feedback.dart';
import 'fullscreen.dart';
import 'gesture_layer.dart';

/// 标准播放器组合 widget。
class StandardPlayer extends StatefulWidget {
  /// 构造标准播放器。
  ///
  /// [controller] 已 initialize 的播放 controller（inline 与全屏页共用同一个）。
  /// [title] 顶栏标题。[inFullscreen] 为 true 时表示当前嵌在全屏页内——
  /// 全屏键变成「退出 / pop」、不再 push，web 不再重复包 scope。
  const StandardPlayer({
    super.key,
    required this.controller,
    this.title = '',
    this.inFullscreen = false,
  });

  /// 播放 controller。
  final NiumaPlayerController controller;

  /// 顶栏标题。
  final String title;

  /// 是否已处于全屏页内。
  final bool inFullscreen;

  @override
  State<StandardPlayer> createState() => _StandardPlayerState();
}

class _StandardPlayerState extends State<StandardPlayer> {
  late final NiumaGestureController _gesture;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _gesture = NiumaGestureController(widget.controller)..initBrightness();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _gesture.dispose();
    super.dispose();
  }

  /// 切控件显隐；显示时重置 3s 自动隐藏计时。
  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _enterFullscreen() {
    // 全屏策略由核 webFullscreenMode 给出，这里只决定 UI：
    switch (webFullscreenMode) {
      case NiumaWebFullscreenMode.nativeVideoElement:
        // iOS Safari：<video> 进系统原生 player（无 Flutter 控件）。
        widget.controller.enterNativeFullscreen();
        return;
      case NiumaWebFullscreenMode.browserElement:
        // Chrome / 桌面：整个画布进浏览器真全屏（必须在此用户手势栈内同步调），
        // 再 push 全屏页让 video + 控件一起铺满。
        requestBrowserFullscreen();
      case NiumaWebFullscreenMode.notWeb:
        break;
    }
    // 全屏切换用「快速淡入」而非 MaterialPageRoute 默认 slide：slide 动画期间
    // 第二个 SurfaceView 创建 + surface 重绑（Android PlatformView 路径）会
    // 掉帧，视觉上「卡一下」。视频 app 全屏切换惯例就是瞬切/快淡。
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 120),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (_, __, ___) => FullscreenPage(
          controller: widget.controller,
          title: widget.title,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NiumaPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final showCover = value.size == Size.zero;
        final showLoading =
            value.phase == PlayerPhase.opening || value.isBuffering;
        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. 画面。Center 把 Stack(expand) 的 tight 约束放松，让
              // NiumaPlayerView 内部的 AspectRatio 真正生效——否则全屏页里
              // AndroidView/SurfaceView 被拉满屏幕，原生缩放直接把画面拉变形
              // （Texture 路径同样受益：非 16:9 视频不再被拉伸）。
              Center(child: NiumaPlayerView(widget.controller)),

              // 2. 封面（首帧前）。
              if (showCover) const CoverLayer(),

              // 3. 手势层（透明捕获 + HUD）。
              GestureLayer(gesture: _gesture, onTap: _toggleControls),

              // 4. loading。
              if (showLoading) const LoadingLayer(),

              // 5. 错误。
              if (value.hasError)
                ErrorLayer(
                  message: value.error?.message ?? '播放出错',
                  onRetry: widget.controller.initialize,
                ),

              // 6. 结束。
              if (value.phase == PlayerPhase.ended)
                EndedLayer(
                  onReplay: () => widget.controller
                    ..seekTo(Duration.zero)
                    ..play(),
                ),

              // 7. 控件层（顶栏 + 底栏，共用一个可见性开关）。
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Column(
                    children: [
                      TopBar(
                        title: widget.title,
                        onBack: Navigator.of(context).canPop()
                            ? () => Navigator.of(context).pop()
                            : null,
                      ),
                      const Spacer(),
                      BottomBar(
                        value: value,
                        isFullscreen: widget.inFullscreen,
                        onPlayPause: value.isPlaying
                            ? widget.controller.pause
                            : widget.controller.play,
                        onSeek: widget.controller.seekTo,
                        onFullscreen: widget.inFullscreen
                            ? () => Navigator.of(context).pop()
                            : _enterFullscreen,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
