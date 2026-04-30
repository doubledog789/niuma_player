import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// M9 demo：用 NiumaPlayer 默认外观渲染一个完整可用的播放页。
///
/// 演示要点：
/// - 5 行起步：拿到 controller → initialize → play → 把 controller 丢进
///   NiumaPlayer。
/// - 默认 B 站风格底部控件条（NiumaControlBar）—— 9 个控件 + scrub bar。
/// - 5 秒不操作自动隐藏；点击切换显隐；暂停时强制显示。
/// - 缩略图 VTT 配置：拖动时进度条上方出现 sprite 缩略图预览（M8 + M9）。
/// - 集成一个 mock pre-roll 广告 cue：演示如何把 [NiumaAdSchedule] 接进来。
/// - 全屏：点击右下 fullscreen 图标 push NiumaFullscreenPage（200ms 淡入
///   + 锁定 landscape + immersiveSticky）。
class M9DefaultDemoPage extends StatefulWidget {
  /// 创建一个 [M9DefaultDemoPage]。
  const M9DefaultDemoPage({super.key});

  @override
  State<M9DefaultDemoPage> createState() => _M9DefaultDemoPageState();
}

class _M9DefaultDemoPageState extends State<M9DefaultDemoPage> {
  late final NiumaPlayerController _controller;

  /// 演示用的 mock 广告 cue——一个紫色全覆盖区，2 秒后才允许 dismiss。
  /// minDisplayDuration 用 controller 自身做闸门。
  late final NiumaAdSchedule _schedule;

  @override
  void initState() {
    super.initState();
    _controller = NiumaPlayerController.dataSource(
      NiumaDataSource.network(
        'https://artplayer.org/assets/sample/bbb-video.mp4',
      ),
      thumbnailVtt: 'https://artplayer.org/assets/sample/bbb-thumbnails.vtt',
    );
    _schedule = NiumaAdSchedule(
      preRoll: AdCue(
        builder: (ctx, ctrl) => Container(
          color: Colors.indigo,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Mock pre-roll 广告',
                  style: TextStyle(color: Colors.white, fontSize: 22),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: ctrl.dismiss,
                  child: const Text('点击跳过（2s 后生效）'),
                ),
              ],
            ),
          ),
        ),
        minDisplayDuration: const Duration(seconds: 2),
        dismissOnTap: false,
      ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('M9 NiumaPlayer 默认外观')),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: NiumaPlayer(
                controller: _controller,
                adSchedule: _schedule,
                adAnalyticsEmitter: (event) {
                  debugPrint('[ad] $event');
                },
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '验证清单：\n'
              '1. 初始进入：底部控件条可见，开始播放后 5s 自动淡出\n'
              '2. 点击视频区切换控件显隐\n'
              '3. 暂停时控件强制显示\n'
              '4. 拖动进度条时上方出现 sprite 缩略图预览（M8 + M9 联动）\n'
              '5. 点击右下 fullscreen 图标进入 NiumaFullscreenPage\n'
              '   （锁定 landscape + immersiveSticky）\n'
              '6. 上方 mock pre-roll 广告 2s 后可跳过；广告显示时控件隐藏',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
