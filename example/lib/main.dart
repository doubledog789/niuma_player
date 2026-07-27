// niuma_player example:
// - minimal_player/: 最小接入，展示 SDK 公共 API 的基本闭环。
// - standard_player/: 基于 headless 核拼出来的完整参考播放器皮。
// - feed_demo/: 短视频 feed 单播放器换源用法（池化预加载另见 NiumaPlayerPool）。
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

/// 四入口菜单：最小接入 / 标准播放器 / 短视频 feed / 内核切换测试。
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
            title: const Text('短视频 Feed（单播放器换源）'),
            subtitle: const Text('停稳后 load() 换源 + iOS Safari 有声连播'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FeedPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('内核切换测试（Exo / IJK）'),
            subtitle: const Text('同一条测试流，运行时切换 Android 内核对比'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EngineSwitchPage()),
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

/// 内核切换测试页：同一条测试流，运行时切 ExoPlayer（硬解）/ IJK（软解）
/// 对比。切换即销毁旧 controller、按所选内核重建（`forceIjkOnAndroid`）。
class EngineSwitchPage extends StatefulWidget {
  const EngineSwitchPage({super.key});

  @override
  State<EngineSwitchPage> createState() => _EngineSwitchPageState();
}

class _EngineSwitchPageState extends State<EngineSwitchPage> {
  // TODO: 换成你自己的测试流地址（mp4 / m3u8 均可）。页面上的输入框可以
  // 运行时替换——签名过期的源不用改代码重编。
  static const String _defaultUrl =
      'https://artplayer.org/assets/sample/bbb-video.mp4';

  late final TextEditingController _urlCtrl =
      TextEditingController(text: _defaultUrl);
  String _url = _defaultUrl;

  /// false = ExoPlayer（默认硬解）；true = 强制 IJK 软解。
  bool _useIjk = false;

  /// PlatformView（SurfaceView 直出）/ Texture（走 Flutter 纹理）。
  /// 排查「解码不出帧」还是「出了帧送不到屏幕」时，两条路要分别试一次。
  bool _usePlatformView = true;

  NiumaPlayerController? _c;

  /// 每次重建 +1，作为播放器子树的 key —— 皮肤 State 跟着换代，
  /// 不会把旧 controller 的监听带到新实例上。
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  Future<void> _rebuild() async {
    final old = _c;
    setState(() => _c = null);
    await old?.dispose();
    final c = NiumaPlayerController.dataSource(
      // TODO: 若你的 CDN 校验 Referer 等请求头，在 headers 里补上，如
      //   headers: const {'referer': 'https://your.domain'}。
      NiumaDataSource.network(_url),
      options: NiumaPlayerOptions(
        useAndroidPlatformView: _usePlatformView,
        forceIjkOnAndroid: _useIjk,
      ),
    );
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() {
      _c = c;
      _generation++;
    });
    // 等 initialize 完成再 play（避免后端就绪前 play 的竞态）；失败由
    // value.phase=error 驱动皮肤错误层显示，无需在这里处理。
    c.initialize().then((_) {
      if (mounted && _c == c) c.play();
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('内核切换测试')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: '测试流 URL',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    setState(() => _url = _urlCtrl.text.trim());
                    _rebuild();
                  },
                  child: const Text('加载'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('ExoPlayer 硬解')),
                ButtonSegment(value: true, label: Text('IJK 软解')),
              ],
              selected: {_useIjk},
              onSelectionChanged: (s) {
                setState(() => _useIjk = s.first);
                _rebuild();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('PlatformView')),
                ButtonSegment(value: false, label: Text('Texture')),
              ],
              selected: {_usePlatformView},
              onSelectionChanged: (s) {
                setState(() => _usePlatformView = s.first);
                _rebuild();
              },
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: c == null
                    ? const Center(child: CircularProgressIndicator())
                    : StandardPlayer(
                        key: ValueKey(_generation),
                        controller: c,
                        title: _useIjk ? 'IJK 软解' : 'ExoPlayer 硬解',
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
