import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// 长视频 demo——演示 M16 inline → 全屏 mockup 风格切换 + 配置驱动 + 业务侧 slot。
///
/// 整合了：
/// - 多 line 切换 (M6)
/// - chapter marks 进度条 (M16)
/// - Cast / PiP (M15 / M12)
/// - 顶栏 title / subtitle 显示 (M16)
/// - 弹幕 hook (M9 disabled + M16 onDanmakuInputTap callback)
/// - bottomActionsBuilder 业务追加（下一集 / 选集）
/// - rightRailBuilder 互动栏（点赞 / 分享）
/// - moreMenuBuilder 三点菜单（字幕设置 / 反馈）
class LongVideoDemoPage extends StatefulWidget {
  const LongVideoDemoPage({super.key});

  @override
  State<LongVideoDemoPage> createState() => _LongVideoDemoPageState();
}

class _LongVideoDemoPageState extends State<LongVideoDemoPage> {
  late final NiumaPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NiumaPlayerController(
      NiumaMediaSource.lines(
        lines: [
          MediaLine(
            id: 'high',
            label: '4K',
            source: NiumaDataSource.network(
              'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
            ),
          ),
          MediaLine(
            id: 'mid',
            label: '1080P',
            source: NiumaDataSource.network(
              'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
            ),
          ),
        ],
        defaultLineId: 'high',
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
      appBar: AppBar(title: const Text('长视频 demo')),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: NiumaPlayer(
              controller: _controller,
              title: '【4K修复】经典动画混剪 致敬童年',
              subtitle: '阿伟动漫研究所 · P1 童年回忆',
              // inline 默认走 M9 9 按钮，全屏切到 mockup bili 预设
              fullscreenControlBarConfig: NiumaControlBarConfig.bili,
              chapters: const [
                Duration(minutes: 2),
                Duration(minutes: 5),
                Duration(minutes: 8),
              ],
              onDanmakuInputTap: _showDanmakuInput,
              moreMenuBuilder: (ctx) => [
                const PopupMenuItem(value: 'subtitle', child: Text('字幕设置')),
                const PopupMenuItem(value: 'report', child: Text('反馈问题')),
              ],
              bottomActionsBuilder: (ctx) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _showSnack('点击：下一集'),
                    child: const Text(
                      '下一集',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showSnack('点击：选集'),
                    child: const Text(
                      '选集 P1',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              rightRailBuilder: (ctx) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RailItem(
                    icon: Icons.favorite,
                    color: const Color(0xFFFB7299),
                    label: '12.3万',
                    onTap: () => _showSnack('点赞'),
                  ),
                  const SizedBox(height: 12),
                  _RailItem(
                    icon: Icons.share_outlined,
                    color: Colors.white,
                    label: '分享',
                    onTap: () => _showSnack('分享'),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '演示：inline 默认 M9 9 按钮；全屏切到 mockup B 站风格（顶栏返回+'
              '标题/副标题+Cast+PiP+线路 pill+三点菜单；中央大圆 PlayPause；'
              '底栏精简；右侧互动栏）；进度条 chapter marks；'
              '弹幕 hook；Cast 分屏 panel；PiP；线路切换。',
            ),
          ),
        ],
      ),
    );
  }

  void _showDanmakuInput() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const Padding(
        padding: EdgeInsets.all(16),
        child: Text('demo 弹幕输入框（业务自实现）'),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: Color(0x73000000),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 1),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 9)),
        ],
      ),
    );
  }
}
