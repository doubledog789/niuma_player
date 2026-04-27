import 'package:flutter/material.dart';

import 'diagnostics_page.dart';
import 'player_page.dart';
import 'samples.dart';

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
