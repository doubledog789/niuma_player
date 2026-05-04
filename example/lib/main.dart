import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player_airplay/niuma_player_airplay.dart';
import 'package:niuma_player_dlna/niuma_player_dlna.dart';

import 'long_video_demo_page.dart';
import 'short_video_demo_page.dart';

void main() {
  // M15: 注册投屏 services
  NiumaCastRegistry.register(DlnaCastService());
  NiumaCastRegistry.register(AirPlayCastService());
  runApp(const NiumaPlayerExampleApp());
}

class NiumaPlayerExampleApp extends StatelessWidget {
  const NiumaPlayerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'niuma_player example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const _Home(),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('niuma_player')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.movie),
            title: const Text('长视频 demo'),
            subtitle: const Text('M16 mockup 全屏 / 线路切换 / Cast / PiP / 弹幕 hook'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LongVideoDemoPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.videocam),
            title: const Text('短视频 demo'),
            subtitle: const Text('竖屏沉浸 / 自动播放'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ShortVideoDemoPage()),
            ),
          ),
        ],
      ),
    );
  }
}
