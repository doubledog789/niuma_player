import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// 演示 `NiumaPlayer` 的两种控件层自定义路径：
///
/// 1. **`fullscreenControlBarConfig`**：声明式 enum 配置——让你不写一行
///    控件代码就能选哪些按钮、放哪一侧、按什么顺序展示。
/// 2. **`buttonOverrides`**：按钮级 override——把某个 enum 槽换成自家
///    BuilderOverride（完全自定义 widget）或 FieldsOverride（沿用 SDK 框
///    架但换 icon / label / onTap）。
/// 3. **`bottomActionsBuilder` / `bottomTrailingBuilder`**：在底栏右组里
///    塞业务自定义 action。
class CustomControlsDemoPage extends StatefulWidget {
  const CustomControlsDemoPage({super.key});

  @override
  State<CustomControlsDemoPage> createState() => _CustomControlsDemoPageState();
}

class _CustomControlsDemoPageState extends State<CustomControlsDemoPage> {
  late final NiumaPlayerController _controller;
  int _episode = 1;

  @override
  void initState() {
    super.initState();
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
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义控件层'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: NiumaPlayer(
                controller: _controller,
                title: '自定义控件 demo',
                subtitle: '第 $_episode 集 · 自定义 UI 演示',
                // 1. 声明式 config——只在底栏左侧塞 playPause + speed，
                //    把 lineSwitch 拿掉（这个 demo 只有单线路），底栏右
                //    侧也清空，让 trailingBuilder / actionsBuilder 接管。
                fullscreenControlBarConfig: const NiumaControlBarConfig(
                  topLeading: [NiumaControlButton.back, NiumaControlButton.title],
                  topActions: [NiumaControlButton.more],
                  bottomLeft: [
                    NiumaControlButton.playPause,
                    NiumaControlButton.speed,
                  ],
                  bottomRight: [],
                  centerPlayPause: true,
                  showProgressBar: true,
                ),
                // 2. 按钮级 override——把 speed 按钮换成自定义文本（demo
                //    意图：演示 BuilderOverride。如果只是换 icon / label，
                //    用 FieldsOverride 更轻量）。
                buttonOverrides: {
                  NiumaControlButton.speed: ButtonOverride.builder((ctx) {
                    return TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('（业务自家速度选择 UI）')),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: const Text(
                        '🚀 极速',
                        style: TextStyle(fontSize: 13),
                      ),
                    );
                  }),
                },
                // 3. 业务侧底栏右组：下一集（bottomActionsBuilder） + 选集
                //    （bottomTrailingBuilder）。两者都在底栏右组里——
                //    bottomActionsBuilder 在 bottomTrailingBuilder 之前。
                bottomActionsBuilder: (ctx) => TextButton.icon(
                  onPressed: () => setState(() => _episode++),
                  icon: const Icon(Icons.skip_next, size: 16),
                  label: const Text('下一集'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                ),
                bottomTrailingBuilder: (ctx) => TextButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('（业务自家选集 panel）')),
                    );
                  },
                  icon: const Icon(Icons.list, size: 16),
                  label: Text('选集 P$_episode'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                ),
                // 4. moreMenuBuilder——⋮ 菜单内追加业务条目（默认有"投屏"
                //    "画中画"两项；web 上隐藏 cast/PiP）。
                moreMenuBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'feedback',
                    child: Row(
                      children: const [
                        Icon(Icons.feedback_outlined,
                            size: 18, color: Colors.white),
                        SizedBox(width: 8),
                        Text('问题反馈'),
                      ],
                    ),
                    onTap: () {
                      final messenger = ScaffoldMessenger.of(context);
                      Future.delayed(const Duration(milliseconds: 100), () {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('（业务反馈页面）')),
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DocBlock(
                    title: 'fullscreenControlBarConfig',
                    body:
                        '声明式 enum 配置：选哪些按钮、放哪侧、按什么顺序。'
                        '自带 minimal / bili / full 三个 preset，业务可写自家 const。',
                  ),
                  SizedBox(height: 8),
                  _DocBlock(
                    title: 'buttonOverrides',
                    body:
                        '把某个 enum 槽换成自家 widget。BuilderOverride 完全自定义；'
                        'FieldsOverride 沿用 SDK 的 IconLabelAction 框架但换 icon/label/onTap。',
                  ),
                  SizedBox(height: 8),
                  _DocBlock(
                    title: 'bottomActions / bottomTrailingBuilder',
                    body:
                        '业务侧底栏右组的两个 slot——典型用例：下一集 + 选集 P*。'
                        '自动在窄屏全屏时跟右组一起换行右对齐。',
                  ),
                  SizedBox(height: 8),
                  _DocBlock(
                    title: 'moreMenuBuilder',
                    body:
                        '⋮ 菜单内追加业务条目。默认菜单含投屏/画中画'
                        '（web 上隐去），业务条目接在分隔线之后。',
                  ),
                ],
              ),
            ),
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
