import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// M12 PiP demo——按钮触发 + autoEnter 切换 + 8 项验证清单。
class M12PipDemoPage extends StatefulWidget {
  /// 创建一个 [M12PipDemoPage]。
  const M12PipDemoPage({super.key});
  @override
  State<M12PipDemoPage> createState() => _M12PipDemoPageState();
}

class _M12PipDemoPageState extends State<M12PipDemoPage> {
  late final NiumaPlayerController _video;

  @override
  void initState() {
    super.initState();
    _video = NiumaPlayerController.dataSource(
      NiumaDataSource.network(
        'https://artplayer.org/assets/sample/bbb-video.mp4',
      ),
    );
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await _video.initialize();
      if (!mounted) return;
      await _video.play();
    } catch (e) {
      debugPrint('init 失败：$e');
    }
  }

  @override
  void dispose() {
    unawaited(_video.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // PiP 模式下藏掉 AppBar / SwitchListTile / 状态打印 / 验证清单——
    // Android PiP 把整个 Activity 缩到迷你窗，AppBar 和说明文字塞在里面
    // 既挤又没意义。只留 player 占满小窗。
    return AnimatedBuilder(
      animation: _video,
      builder: (ctx, _) {
        final inPip = _video.value.isInPictureInPicture;
        return Scaffold(
          appBar: inPip ? null : AppBar(title: const Text('M12 PiP demo')),
          backgroundColor: Colors.black,
          body: SingleChildScrollView(
            physics: inPip
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ColoredBox(
                    color: Colors.black,
                    child: NiumaPlayer(controller: _video),
                  ),
                ),
                if (!inPip) ...[
                  SwitchListTile(
                    title: const Text('app 切后台时自动进 PiP'),
                    subtitle: const Text(
                      '只在 phase=playing 时才生效',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _video.autoEnterPictureInPictureOnBackground,
                    onChanged: (v) {
                      setState(() {
                        _video.autoEnterPictureInPictureOnBackground = v;
                      });
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('isPictureInPictureSupported: '
                            '${_video.value.isPictureInPictureSupported}'),
                        Text('isInPictureInPicture: '
                            '${_video.value.isInPictureInPicture}'),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '验证清单：\n'
                      '1. 右上角 PipButton：点击进入系统 PiP 窗\n'
                      '2. iOS：PiP 窗内 stock 控件（play/pause/timeline/close）工作\n'
                      '3. Android：PiP 窗内 play/pause action 按钮工作\n'
                      '4. autoEnter 开 → home 键 / 上滑 home → 自动进 PiP\n'
                      '5. autoEnter 关 → home 键 → 视频后台暂停（不自动 PiP）\n'
                      '6. 从 PiP 拖回主 app → 视频回到原位继续播\n'
                      '7. 不支持设备：右上 PipButton 灰禁\n'
                      '8. PiP 中切换全屏页 → 状态保持',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
