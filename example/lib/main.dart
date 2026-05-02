import 'package:flutter/material.dart';

import 'diagnostics_page.dart';
import 'm11_danmaku_demo_page.dart';
import 'm12_pip_demo_page.dart';
import 'm13_gesture_demo_page.dart';
import 'm14_short_video_demo_page.dart';
import 'm9_custom_demo_page.dart';
import 'm9_default_demo_page.dart';
import 'multi_line_page.dart';
import 'player_page.dart';
import 'samples.dart';
import 'thumbnail_demo_page.dart';

void main() {
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
      home: const HomeScreen(),
    );
  }
}

/// Menu of demo scenarios. Each card opens a player page configured for a
/// specific test case (loop, force-IJK, error path, etc.).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('niuma_player example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const _SectionHeader('视频示例'),
          for (final sample in samples)
            _SampleCard(
              sample: sample,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PlayerPage(sample: sample),
                ),
              ),
            ),

          const SizedBox(height: 24),
          const _SectionHeader('M9 UI overlay 演示'),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.smart_display),
              title: const Text('NiumaPlayer 默认外观'),
              subtitle: const Text(
                '5 行起步：B 站风格底栏 + auto-hide + 缩略图 + 全屏 + mock 广告',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const M9DefaultDemoPage(),
                ),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.dashboard_customize),
              title: const Text('积木拼自定义布局'),
              subtitle: const Text(
                '原子控件 + 自定义主题：控件分上下 + 紫色 accent',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const M9CustomDemoPage(),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
          const _SectionHeader('M11 弹幕 demo'),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.chat),
              title: const Text('弹幕完整 demo'),
              subtitle: const Text(
                'mock 60s 桶 lazy load + 三模式 + 设置面板 + echo 注入',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const M11DanmakuDemoPage(),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
          const _SectionHeader('M12 PiP demo'),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.picture_in_picture_alt),
              title: const Text('PiP 画中画 demo'),
              subtitle: const Text(
                '按钮触发 + autoEnter 切换 + 8 项验证清单',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const M12PipDemoPage(),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
          const _SectionHeader('M13 手势 demo'),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.touch_app),
              title: const Text('视频手势 demo'),
              subtitle: const Text(
                '双击/seek/亮度/音量/长按倍速 5 项手势 + inline 开关',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const M13GestureDemoPage(),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
          const _SectionHeader('M14 短视频 demo'),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.video_collection),
              title: const Text('M14: 短视频流（PageView）'),
              subtitle: const Text(
                'PageView 竖向滑动 · 3 个样本视频 · 爱心/评论/分享 overlay',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const M14ShortVideoDemoPage(),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
          const _SectionHeader('M8 缩略图 VTT 演示'),
          for (final t in thumbnailVttSamples)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.image_search),
                title: Text(t.label),
                subtitle: const Text(
                  '拖动进度条时显示 sprite 缩略图预览',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ThumbnailDemoPage(sample: t),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 24),
          const _SectionHeader('M7 多线路演示'),
          for (final ml in multiLineSamples)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(ml.label),
                subtitle: Text(
                  '${ml.lines.length} 条线路 · 验证 switchLine + middleware',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => MultiLinePlayerPage(sample: ml),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 24),
          const _SectionHeader('调试 / 诊断'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('设备指纹 + 失败记忆'),
              subtitle: const Text(
                '查看 native DeviceMemoryStore 内容；'
                '验证 M3.1 持久化',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const DiagnosticsPage(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.sample, required this.onTap});

  final Sample sample;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tags = <Widget>[];
    if (sample.forceIjkOnAndroid) {
      tags.add(_tag('Force IJK', Colors.deepOrange));
    }
    if (sample.startsLooping) {
      tags.add(_tag('Loop', Colors.green));
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Row(
          children: <Widget>[
            Expanded(child: Text(sample.label)),
            for (final t in tags) ...<Widget>[const SizedBox(width: 4), t],
          ],
        ),
        subtitle: Text(
          sample.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
        trailing: const Icon(Icons.play_arrow),
        onTap: onTap,
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
    );
  }
}
