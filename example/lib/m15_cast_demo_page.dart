import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// M15 投屏 demo——支持 DLNA + AirPlay 投屏，含 8 项验证清单。
class M15CastDemoPage extends StatefulWidget {
  const M15CastDemoPage({super.key});

  @override
  State<M15CastDemoPage> createState() => _M15CastDemoPageState();
}

class _M15CastDemoPageState extends State<M15CastDemoPage> {
  late final NiumaPlayerController _video;

  @override
  void initState() {
    super.initState();
    _video = NiumaPlayerController.dataSource(
      NiumaDataSource.network(
        'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_5MB.mp4',
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
      appBar: AppBar(title: const Text('M15 投屏 demo')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: NiumaPlayer(controller: _video),
              ),
            ),
            ValueListenableBuilder<CastSession?>(
              valueListenable: _video.castSession,
              builder: (ctx, session, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前 castSession: ${session?.device.name ?? "<未投屏>"}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (session != null) ...[
                      const SizedBox(height: 4),
                      Text('protocol: ${session.device.protocolId}'),
                      Text('device id: ${session.device.id}'),
                    ],
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '验证清单：\n'
                '1. 点视频右下 cast 按钮 → bottom sheet 弹出，扫描中 chip 显示\n'
                '2. 8 秒内扫到至少 1 台设备\n'
                '3. tap 设备 → 主页"投屏中"覆盖层 + cast 按钮高亮 + 显示设备名\n'
                '4. 投屏中点 ▶ / ⏸ → TV 端响应\n'
                '5. 投屏中拖 ScrubBar → TV 端跳到对应位置\n'
                '6. 投屏中再点 cast 按钮 → 简化 picker（切换 / 断开）\n'
                '7. 点"断开投屏" → 本地继续播，进度接续\n'
                '8. 关闭 WiFi 模拟掉线 → SDK 自动 fallback 本地恢复',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
