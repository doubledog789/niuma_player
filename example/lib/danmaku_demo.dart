import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// 演示 SDK 的弹幕系统集成：
///
/// 1. **`NiumaDanmakuController`**：业务侧自管的弹幕数据源——`add(item)` /
///    `addAll(items)` 注入；`updateSettings(...)` 改字号 / 透明度 / 显示区域。
/// 2. **`NiumaPlayer.danmakuController`**：把 controller 透传给 player，SDK
///    自动渲染 `NiumaDanmakuOverlay`（弹幕飘动层）。
/// 3. **`NiumaPlayer.onDanmakuInputTap`**：底栏弹幕输入框被点时的 callback——
///    业务在这里 push 自家弹幕输入页（不限定 UI），拿到结果再 `controller.add`。
/// 4. **bottomTrailingBuilder + DanmakuSettingsPanel**：演示通过 sheet 弹出
///    SDK 自带的弹幕设置面板（字号 / 透明度 / 显示区域）。
class DanmakuDemoPage extends StatefulWidget {
  const DanmakuDemoPage({super.key});

  @override
  State<DanmakuDemoPage> createState() => _DanmakuDemoPageState();
}

class _DanmakuDemoPageState extends State<DanmakuDemoPage> {
  late final NiumaPlayerController _controller;
  late final NiumaDanmakuController _danmaku;

  @override
  void initState() {
    super.initState();
    _danmaku = NiumaDanmakuController()..addAll(_mockDanmaku());
    _controller = NiumaPlayerController(
      NiumaMediaSource.single(
        NiumaDataSource.network(
          'https://artplayer.org/assets/sample/bbb-video.mp4',
        ),
      ),
    );
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _danmaku.dispose();
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// mock 30 条弹幕，撒在前 60 秒里——演示用。
  /// 实际业务里弹幕一般从 API 拉，构造同样的 [DanmakuItem]。
  List<DanmakuItem> _mockDanmaku() {
    const texts = [
      'awsl 这画面太顶了',
      '爷青回',
      '前方高能',
      '这 BGM 我能单曲循环',
      '哈哈哈哈哈哈',
      '2026 年还在看',
      '兔子好可爱',
      '画质修复牛',
      '弹幕护体',
      '已三连',
      '永远的神',
      '太破防了',
      '这一段好评',
      '23333',
      '我去',
    ];
    const colors = [
      Color(0xFFFFFFFF),
      Color(0xFFFFD93D),
      Color(0xFFFF6B6B),
      Color(0xFF6BCB77),
      Color(0xFF4D96FF),
    ];
    final r = Random(42);
    return List.generate(30, (i) {
      return DanmakuItem(
        position: Duration(milliseconds: i * 1800 + r.nextInt(1000)),
        text: texts[i % texts.length],
        color: colors[r.nextInt(colors.length)],
        fontSize: 16 + r.nextInt(4).toDouble(),
      );
    });
  }

  /// 业务侧"发弹幕"流程——这里弹一个 dialog 让用户输入；真实业务可以
  /// push route 到富 UI 输入页（emoji / 颜色选择器 / 表情包等）。
  Future<void> _showDanmakuInput(BuildContext ctx) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('发弹幕', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '友善评论，从我做起',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dctx).pop(controller.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    // 把用户输入的弹幕加到当前播放位置——SDK 弹幕 overlay 监听 controller，
    // 立刻飘出来。
    _danmaku.add(DanmakuItem(
      position: _controller.value.position,
      text: text,
      color: const Color(0xFFEF9F27),
      fontSize: 18,
    ));
  }

  /// 弹出 SDK 自带的设置面板——字号 / 透明度 / 显示区域 % 三档可调。
  /// 业务方想自己做面板的话不用这个 widget，直接 `_danmaku.updateSettings(...)`。
  Future<void> _showDanmakuSettings(BuildContext ctx) async {
    await showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: const Color(0xFF252526),
      builder: (sctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DanmakuSettingsPanel(danmaku: _danmaku),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('弹幕集成')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: NiumaPlayer(
                controller: _controller,
                danmakuController: _danmaku,
                title: '弹幕集成 demo',
                subtitle: '点底栏发弹幕 / 长按设置',
                // 底栏弹幕输入框 (DanmakuInputPill) 被点时调本 callback——
                // 业务自定义弹幕输入 UI 时挂在这里。
                onDanmakuInputTap: () => _showDanmakuInput(context),
                // 全屏底栏右组追加"设置"入口，演示业务侧调出 SDK 自带的
                // DanmakuSettingsPanel。
                bottomTrailingBuilder: (ctx) => TextButton.icon(
                  onPressed: () => _showDanmakuSettings(context),
                  icon: const Icon(Icons.tune, size: 16, color: Colors.white),
                  label: const Text(
                    '弹幕设置',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DocBlock(
                    title: 'NiumaDanmakuController',
                    body:
                        '业务侧自管弹幕数据源——initState 里创建 + addAll(items)，'
                        'dispose 时记得 .dispose()。注入给 NiumaPlayer.danmakuController '
                        '后 SDK 自动渲染 NiumaDanmakuOverlay 飘动层。',
                  ),
                  SizedBox(height: 8),
                  _DocBlock(
                    title: 'onDanmakuInputTap',
                    body:
                        '底栏弹幕输入 pill 被点时的 callback。SDK **不实现**弹幕输入 UI'
                        '——业务在这里 push 自家输入页（emoji / 颜色 / 表情包等），拿到 '
                        '结果调 _danmaku.add(DanmakuItem(...))。',
                  ),
                  SizedBox(height: 8),
                  _DocBlock(
                    title: 'DanmakuSettingsPanel',
                    body:
                        'SDK 自带的字号 / 透明度 / 显示区域 设置面板。业务想自定义 UI '
                        '不用这个 widget，直接 _danmaku.updateSettings(...).',
                  ),
                  SizedBox(height: 8),
                  _DocBlock(
                    title: 'DanmakuItem',
                    body:
                        'position / text 必填，color / fontSize / mode（rolling / top / '
                        'bottom）选填。业务从 API 拉的数据按这个 schema 转就行。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _DocBlock extends StatelessWidget {
  const _DocBlock({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFEF9F27),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
