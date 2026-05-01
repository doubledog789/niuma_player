import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// M9 demo：用 9 个原子控件 + NiumaPlayerView + NiumaScrubPreview 自己拼一
/// 套**非默认**布局。
///
/// 演示要点：
/// - 控件条放在视频**上方**，不是默认的下方。
/// - 把按钮分两行：第一行是大号 PlayPauseButton + TimeDisplay，第二行
///   是次级控件（speed / quality / volume / fullscreen）。
/// - 进度条放在视频**下方**单独占一行，hover 缩略图依然有。
/// - 自定义 NiumaPlayerTheme：紫色 accent + 更大 thumbRadius。
class M9CustomDemoPage extends StatefulWidget {
  /// 创建一个 [M9CustomDemoPage]。
  const M9CustomDemoPage({super.key});

  @override
  State<M9CustomDemoPage> createState() => _M9CustomDemoPageState();
}

class _M9CustomDemoPageState extends State<M9CustomDemoPage> {
  late final NiumaPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NiumaPlayerController.dataSource(
      NiumaDataSource.network(
        'https://artplayer.org/assets/sample/bbb-video.mp4',
      ),
      thumbnailVtt: 'https://artplayer.org/assets/sample/bbb-thumbnails.vtt',
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      await _controller.play();
    } catch (e) {
      debugPrint('initialize 失败：$e');
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const theme = NiumaPlayerTheme(
      accentColor: Colors.deepPurpleAccent,
      scrubBarThumbRadius: 8,
      scrubBarThumbRadiusActive: 12,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('M9 积木自定义布局')),
      // 深色背景：默认 NiumaPlayerTheme 用白色 icon / 高对比配色，
      // 直接放在 Scaffold 默认白底上会"白上加白"看不见。
      backgroundColor: Colors.black87,
      body: NiumaPlayerThemeData(
        data: theme,
        // SingleChildScrollView 防 overflow：横→竖屏过渡的瞬间布局
        // 收紧，没 scroll 容器会 RenderFlex overflow。
        child: SingleChildScrollView(
          child: Column(
            children: [
            // 第一行：主操作（播放 + 时间显示）。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  PlayPauseButton(controller: _controller),
                  const SizedBox(width: 12),
                  TimeDisplay(controller: _controller),
                ],
              ),
            ),
            // 视频本体。
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: NiumaPlayerView(_controller),
              ),
            ),
            // 进度条独占一行（hover 缩略图仍可用）。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ScrubBar(controller: _controller),
            ),
            // 第二行：次级控件。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  SpeedSelector(controller: _controller),
                  QualitySelector(controller: _controller),
                  VolumeButton(controller: _controller),
                  const Spacer(),
                  FullscreenButton(controller: _controller),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '验证清单：\n'
                '1. 控件分散在视频上下三个区域（上 / 进度条 / 下）\n'
                '2. 紫色 accent + 加大 thumb 半径来自 NiumaPlayerTheme 注入\n'
                '3. 拖动进度条时 ScrubBar 顶上出现缩略图预览\n'
                '4. 全屏按钮仍然 push NiumaFullscreenPage',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
