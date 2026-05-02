import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// M13 demo：手势 5 项 + inline 切换 + 验证清单。
class M13GestureDemoPage extends StatefulWidget {
  /// 创建一个 [M13GestureDemoPage]。
  const M13GestureDemoPage({super.key});
  @override
  State<M13GestureDemoPage> createState() => _M13GestureDemoPageState();
}

class _M13GestureDemoPageState extends State<M13GestureDemoPage> {
  late final NiumaPlayerController _video;
  bool _enableInline = false;

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
    return Scaffold(
      appBar: AppBar(title: const Text('M13 手势 demo')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: NiumaPlayer(
                  controller: _video,
                  gesturesEnabledInline: _enableInline,
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('inline 启用手势'),
              subtitle: const Text(
                '默认仅全屏页生效；开了竖屏页也能用',
                style: TextStyle(fontSize: 11),
              ),
              value: _enableInline,
              onChanged: (v) => setState(() => _enableInline = v),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '验证清单：\n'
                '1. 全屏内双击 → 切换播放/暂停\n'
                '2. 全屏内水平滑 → seek（HUD 显示 +Ns / 当前 / 总）\n'
                '3. 全屏内左半屏垂直滑 → 亮度变化（HUD 显示百分比）\n'
                '4. 全屏内右半屏垂直滑 → 音量变化（HUD 显示百分比）\n'
                '5. 全屏内长按视频区 → 切到 2x，松手回原速\n'
                '6. 退出全屏 → 系统亮度恢复\n'
                '7. 关 inline → 竖屏页 pan 无反应\n'
                '8. 开 inline → 竖屏页同样支持',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
