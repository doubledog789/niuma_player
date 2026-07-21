// niuma_player example:
// - minimal_player/: 最小接入，展示 SDK 公共 API 的基本闭环。
// - standard_player/: 基于 headless 核拼出来的完整参考播放器皮。
// - feed_demo/: 短视频/短剧 feed 中的播放器池用法。
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

import 'feed_demo/feed_page.dart';
import 'minimal_player/minimal_player.dart';
import 'standard_player/standard_player.dart';

void main() => runApp(const StandardDemoApp());

class StandardDemoApp extends StatelessWidget {
  const StandardDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'niuma_player 示例',
      home: HomePage(),
    );
  }
}

/// 三入口菜单：最小接入 / 标准播放器 / 短视频 feed（播放器池）。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('niuma_player 示例')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.play_arrow_outlined),
            title: const Text('最小播放器'),
            subtitle: const Text('controller + view + 基础控件'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MinimalPlayerPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('标准播放器参考皮'),
            subtitle: const Text('顶栏 / 底栏 / 手势 / 全屏'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StandardPlayerPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.video_collection_outlined),
            title: const Text('短视频 Feed（播放器池）'),
            subtitle: const Text('翻页预加载 + 复用 + 防 OOM'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FeedPage()),
            ),
          ),
        ],
      ),
    );
  }
}

class StandardPlayerPage extends StatefulWidget {
  const StandardPlayerPage({super.key});

  @override
  State<StandardPlayerPage> createState() => _StandardPlayerPageState();
}

class _StandardPlayerPageState extends State<StandardPlayerPage> {
  late final NiumaPlayerController _c;

  @override
  void initState() {
    super.initState();
    _c = NiumaPlayerController.dataSource(
      NiumaDataSource.network(
        'https://artplayer.org/assets/sample/bbb-video.mp4',
      ),
      options: const NiumaPlayerOptions(useAndroidPlatformView: true),
    );
    // 等 initialize 完成再 play —— 直接 ..initialize() 后立刻 play() 会在
    // 后端就绪前调用,自动播放不生效（竞态）。
    _c.initialize().then((_) {
      if (mounted) _c.play();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('niuma_player 标准 UI 示例'),
        actions: [
          // iPhone Safari：standard player 的全屏按钮叠在 <video> 上、被
          // platform-view 吞点不动；在 AppBar（视频画面外、能点）放一个全屏
          // 入口，触发 enterNativeFullscreen → webkitEnterFullscreen 系统全屏。
          if (webFullscreenMode == NiumaWebFullscreenMode.nativeVideoElement)
            IconButton(
              icon: const Icon(Icons.fullscreen),
              tooltip: '进入全屏',
              onPressed: () => _c.enterNativeFullscreen(),
            ),
        ],
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: StandardPlayer(controller: _c, title: 'Big Buck Bunny'),
        ),
      ),
    );
  }
}
