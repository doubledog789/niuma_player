// example/lib/m14_short_video_demo_page.dart
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// M14 短视频 PageView 示例。
class M14ShortVideoDemoPage extends StatefulWidget {
  const M14ShortVideoDemoPage({super.key});

  @override
  State<M14ShortVideoDemoPage> createState() => _M14ShortVideoDemoPageState();
}

class _M14ShortVideoDemoPageState extends State<M14ShortVideoDemoPage> {
  // 用 test-videos.co.uk 的样本（与项目其他 demo 同源）。
  // 三个不同分辨率/编码，模拟短视频流多样性。
  static const _samples = [
    'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_5MB.mp4',
    'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4',
    'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h265/1080/Big_Buck_Bunny_1080_10s_1MB.mp4',
  ];

  late final List<NiumaPlayerController> _controllers;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controllers = _samples
        .map((url) => NiumaPlayerController.dataSource(
              NiumaDataSource.network(url),
            ))
        .toList();
    for (final c in _controllers) {
      c.initialize();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: _samples.length,
        onPageChanged: (idx) => setState(() => _currentPage = idx),
        itemBuilder: (ctx, idx) => NiumaShortVideoPlayer(
          controller: _controllers[idx],
          isActive: idx == _currentPage,
          overlayBuilder: (ctx, value) => Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 60),
            child: Align(
              alignment: Alignment.bottomRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.favorite_border, color: Colors.white, size: 36),
                  SizedBox(height: 4),
                  Text('1.2k', style: TextStyle(color: Colors.white)),
                  SizedBox(height: 16),
                  Icon(Icons.comment, color: Colors.white, size: 36),
                  SizedBox(height: 4),
                  Text('234', style: TextStyle(color: Colors.white)),
                  SizedBox(height: 16),
                  Icon(Icons.share, color: Colors.white, size: 36),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
