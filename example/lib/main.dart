// niuma_player headless 核的最小用法示例。
//
// 这里只演示「怎么接 headless 核 + 自己拼最基础 UI」：用
// NiumaPlayerController 驱动播放，NiumaPlayerView 渲染画面，再用
// ValueListenableBuilder 监听 NiumaPlayerValue 自己拼一个播放/暂停 +
// 进度条。UI 自己写或让 AI 按需生成；复杂功能（全屏 / 手势 / 弹幕 /
// cast / 广告）看 git 历史里的 example/lib/niuma_ui 参考实现。
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

void main() => runApp(const MinimalDemoApp());

class MinimalDemoApp extends StatelessWidget {
  const MinimalDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'niuma_player 最小示例',
      home: PlayerPage(),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final NiumaPlayerController _c;

  @override
  void initState() {
    super.initState();
    _c = NiumaPlayerController.dataSource(
      NiumaDataSource.network(
        'https://artplayer.org/assets/sample/bbb-video.mp4',
      ),
    )..initialize();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('niuma_player 最小示例')),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: NiumaPlayerView(_c),
          ),
          ValueListenableBuilder<NiumaPlayerValue>(
            valueListenable: _c,
            builder: (context, value, _) {
              final position = value.position;
              final duration = value.duration;
              final maxMs = duration.inMilliseconds;
              return Row(
                children: [
                  IconButton(
                    icon: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: value.isPlaying ? _c.pause : _c.play,
                  ),
                  Expanded(
                    child: Slider(
                      value:
                          position.inMilliseconds.clamp(0, maxMs).toDouble(),
                      max: maxMs > 0 ? maxMs.toDouble() : 1,
                      onChanged: maxMs > 0
                          ? (v) => _c.seekTo(Duration(milliseconds: v.round()))
                          : null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '${formatVideoTime(position)} / '
                      '${formatVideoTime(duration)}',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
