// example/lib/m14_short_video_demo_page.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// M14 短视频 PageView 示例。
///
/// 每条短视频带一个独立 [NiumaDanmakuController]，演示弹幕在短视频沉浸 UX
/// 中的渲染（透传到全屏后弹幕也跟过去）。
class M14ShortVideoDemoPage extends StatefulWidget {
  /// 创建 demo。
  const M14ShortVideoDemoPage({super.key});

  @override
  State<M14ShortVideoDemoPage> createState() => _M14ShortVideoDemoPageState();
}

class _M14ShortVideoDemoPageState extends State<M14ShortVideoDemoPage> {
  // 用 test-videos.co.uk 的样本（与项目其他 demo 同源）。
  // 三个不同分辨率/编码，模拟短视频流多样性。
  // 三条都用 H.264——iOS video_player 解 H.265 在某些 profile 下黑屏不报错。
  // 改用不同分辨率的 H.264 模拟短视频流多样性。
  static const _samples = [
    'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_5MB.mp4',
    'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_2MB.mp4',
    'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4',
  ];

  late final List<NiumaPlayerController> _controllers;
  late final List<NiumaDanmakuController> _danmakuControllers;
  final _random = math.Random(42);
  Timer? _autoInjectTimer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controllers = _samples
        .map((url) => NiumaPlayerController.dataSource(
              NiumaDataSource.network(url),
            ))
        .toList();
    _danmakuControllers = List.generate(
      _samples.length,
      (idx) => NiumaDanmakuController(loader: _mockLoader),
    );
    for (final c in _controllers) {
      c.initialize();
    }
    // 每 1.5s 给当前可见的视频再注入一条新弹幕（模拟实时发送）
    _autoInjectTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      _injectNow(_currentPage);
    });
  }

  /// mock loader：每 60s 桶 50 条样本弹幕，三模式混合。
  FutureOr<List<DanmakuItem>> _mockLoader(Duration s, Duration e) async {
    return List.generate(50, (i) {
      final ms = s.inMilliseconds +
          _random.nextInt(
              math.max(1, e.inMilliseconds - s.inMilliseconds));
      final mode = DanmakuMode.values[_random.nextInt(3)];
      return DanmakuItem(
        position: Duration(milliseconds: ms),
        text: _samplePhrases[_random.nextInt(_samplePhrases.length)],
        fontSize: 18 + _random.nextInt(6).toDouble(),
        color: Color(0xFF000000 | _random.nextInt(0xFFFFFF))
            .withValues(alpha: 1),
        mode: mode,
      );
    });
  }

  void _injectNow(int idx) {
    final video = _controllers[idx];
    final danmaku = _danmakuControllers[idx];
    final mode = DanmakuMode.values[_random.nextInt(3)];
    danmaku.add(DanmakuItem(
      position: video.value.position,
      text: '即时弹幕 ${DateTime.now().millisecondsSinceEpoch % 10000}',
      color: const Color(0xFFFFD54F),
      fontSize: 20,
      mode: mode,
    ));
  }

  static const _samplePhrases = <String>[
    '哈哈哈',
    '前方高能',
    '666',
    '这画面绝了',
    '路过打卡',
    '挺好看',
    '鸡你太美',
    '已三连',
    '首页推荐我来的',
    '好评',
    '楼下沙发',
    '这转场牛',
    '收藏夹+1',
    '画质清晰',
    '弹幕护体',
  ];

  @override
  void dispose() {
    _autoInjectTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final dc in _danmakuControllers) {
      dc.dispose();
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
          // 默认是 cover（抖音风裁切填满）；但样本是 16:9 横屏，
          // cover 会把两侧裁掉。这里改 contain 保留比例（上下黑边）。
          // 真实抖音内容（竖屏 9:16）不需要改这个，cover 默认值就对。
          fit: BoxFit.contain,
          // 弹幕集成：每个 PageView item 独立 controller，全屏后跟过去
          danmakuController: _danmakuControllers[idx],
          leftCenterBuilder: (ctx, c) => NiumaShortVideoFullscreenButton(
            controller: c,
            danmakuController: _danmakuControllers[idx],
          ),
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
