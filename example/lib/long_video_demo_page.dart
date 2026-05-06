import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// 长视频 demo——演示 M16 inline → 全屏 mockup 风格切换 + 配置驱动 + 业务侧 slot。
///
/// 整合了：
/// - bbb-video（10 分钟 Big Buck Bunny，国内可访问）+ VTT 缩略图 (M8)
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
  late final NiumaDanmakuController _danmaku;

  @override
  void initState() {
    super.initState();
    _danmaku = NiumaDanmakuController()
      ..addAll(_mockDanmaku());
    _controller = NiumaPlayerController(
      NiumaMediaSource.lines(
        lines: [
          MediaLine(
            id: 'line1',
            label: '线路一',
            source: NiumaDataSource.network(
              'https://artplayer.org/assets/sample/bbb-video.mp4',
            ),
          ),
          MediaLine(
            id: 'line2',
            label: '线路二',
            source: NiumaDataSource.network(
              'https://artplayer.org/assets/sample/bbb-video.mp4',
            ),
          ),
        ],
        defaultLineId: 'line1',
        thumbnailVtt:
            'https://artplayer.org/assets/sample/bbb-thumbnails.vtt',
      ),
      // ⚠️ demo 启用 PiP "点击即自动退后台"——会让 host app 失去上 App
      // Store 资格，仅适合 Ad Hoc / Enterprise / 越狱设备。详见
      // [NiumaPlayerOptions.unsafePipAutoBackgroundOnEnter] 文档。
      options: const NiumaPlayerOptions(
        unsafePipAutoBackgroundOnEnter: true,
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
    _danmaku.dispose();
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// mock 几条弹幕——按视频播放进度时间撒在 0-10 分钟内。
  List<DanmakuItem> _mockDanmaku() {
    const texts = [
      'awsl 这画面太顶了',
      '爷青回!!!',
      '前方高能',
      '这BGM我能单曲循环',
      '哈哈哈哈哈哈',
      '2026 年还在看',
      '兔子好可爱',
      '画质修复牛',
      '弹幕护体',
      '已三连',
    ];
    final colors = [
      const Color(0xFFFFFFFF),
      const Color(0xFFFFD93D),
      const Color(0xFFFB7299),
      const Color(0xFF6DECAF),
      const Color(0xFF87CEFA),
    ];
    final items = <DanmakuItem>[];
    for (var i = 0; i < texts.length; i++) {
      items.add(DanmakuItem(
        position: Duration(seconds: 3 + i * 4),
        text: texts[i],
        color: colors[i % colors.length],
        fontSize: 18,
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: NiumaPlayer(
              controller: _controller,
              danmakuController: _danmaku,
              gesturesEnabledInline: true,
              title: '【4K修复】经典动画混剪 致敬童年',
              subtitle: '阿伟动漫研究所 · P1 童年回忆',
              // inline 显式给 config 走 _ConfigDrivenBar，避开 M9 _LegacyM9Bar
              // 在 <420dp 屏宽下 hide 9 按钮的行为。
              controlBarConfig: const NiumaControlBarConfig(
                bottomLeft: [
                  NiumaControlButton.playPause,
                  NiumaControlButton.timeDisplay,
                  NiumaControlButton.speed,
                ],
                bottomRight: [NiumaControlButton.fullscreen],
              ),
              // 关掉 mockup 中央大圆 PlayPause——避免和 M13 双击 hud 重复
              // 显示。底栏 PlayPauseButton + 双击切换已经够用。
              fullscreenControlBarConfig: const NiumaControlBarConfig(
                topLeading: [
                  NiumaControlButton.back,
                  NiumaControlButton.title,
                ],
                topActions: [NiumaControlButton.more],
                bottomLeft: [
                  NiumaControlButton.playPause,
                  NiumaControlButton.volume,
                  NiumaControlButton.danmakuToggle,
                  NiumaControlButton.danmakuInput,
                ],
                bottomRight: [
                  NiumaControlButton.speed,
                  NiumaControlButton.lineSwitch,
                ],
                centerPlayPause: false,
                showProgressBar: true,
              ),
              chapters: const [
                Duration(minutes: 2),
                Duration(minutes: 5),
                Duration(minutes: 8),
              ],
              onDanmakuInputTap: _showDanmakuInput,
              actionsBuilder: (ctx) => Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  _TopActionButton(icon: Icons.thumb_up_outlined, label: '6.1万'),
                  SizedBox(width: 12),
                  _TopActionButton(icon: Icons.share_outlined, label: '分享'),
                  SizedBox(width: 12),
                ],
              ),
              moreMenuBuilder: (ctx) => [
                const PopupMenuItem(value: 'report', child: Text('反馈问题')),
              ],
              bottomActionsBuilder: (ctx) => TextButton(
                onPressed: () => _showSnack('点击：下一集'),
                child: const Text(
                  '下一集',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              bottomTrailingBuilder: (ctx) => TextButton(
                onPressed: () => _showSnack('点击：选集'),
                child: const Text(
                  '选集 P1',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              rightRailBuilder: (ctx) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RailItem(
                    icon: Icons.favorite,
                    color: const Color(0xFFFB7299), // B 站粉——「点赞」语义色
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
              // 短视频风格 pause indicator——paused 时中央显示，play 后
              // 立刻消失。inline + fullscreen 都生效（NiumaPlayer 内部
              // ValueListenableBuilder 监听 controller，全屏页通过
              // NiumaPlayerConfigScope 透传也接到）。可点击：tap → play。
            
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '演示：inline 自定义 4 按钮 (PlayPause/Time/Speed/Fullscreen)；'
              '全屏切到 mockup B 站风格（顶栏返回+标题/副标题+Cast+PiP+'
              '线路 pill+三点菜单；中央大圆 PlayPause；底栏精简；右侧互动栏）；'
              '进度条 chapter marks；VTT 缩略图（拖动几秒后再 scrub）；'
              '弹幕 hook；Cast 分屏 panel；PiP。\n\n'
              '资源：artplayer.org bbb-video.mp4（10 分钟 Big Buck Bunny）+ '
              'bbb-thumbnails.vtt 缩略图 sprite。',
            ),
          ),
        ],
      ),
    );
  }

  void _showDanmakuInput() {
    final textCtl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '发条友善的弹幕',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: textCtl,
                autofocus: true,
                maxLength: 30,
                decoration: const InputDecoration(
                  hintText: '说点什么...',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitDanmaku(textCtl.text, sheetCtx),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _submitDanmaku(textCtl.text, sheetCtx),
                    child: const Text('发送'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _submitDanmaku(String raw, BuildContext sheetCtx) {
    final text = raw.trim();
    if (text.isEmpty) return;
    // 用当前播放进度作为弹幕 position——下一次播放也能复现这条。
    final pos = _controller.value.position;
    _danmaku.add(DanmakuItem(
      position: pos,
      text: text,
      color: const Color(0xFFFB7299),
      fontSize: 18,
    ));
    Navigator.of(sheetCtx).pop();
    _showSnack('弹幕已发送：$text');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 9),
        ),
      ],
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
