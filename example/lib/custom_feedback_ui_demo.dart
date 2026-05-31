import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player_example/niuma_ui/niuma_ui.dart';

/// 演示 `NiumaPlayer` 的三态反馈 UI 自定义 slot：
///
/// - **`loadingBuilder`**：phase=opening / buffering 时渲染（默认 [NiumaLoadingIndicator]）
/// - **`errorBuilder`**：phase=error 时渲染（默认 [NiumaErrorView]）
/// - **`endedBuilder`**：phase=ended 时渲染（默认 [NiumaEndedView]）
/// - **`onErrorRetry`** / **`onEndedReplay`**：默认 UI 的回调（业务自定义 UI 可忽略）
///
/// 同时演示 `NiumaProgressThumb.iconBuilder`——拖动进度条时的 thumb 头像
/// 自定义。这里换成业务 logo（颜色块）演示。
class CustomFeedbackUiDemoPage extends StatefulWidget {
  const CustomFeedbackUiDemoPage({super.key});

  @override
  State<CustomFeedbackUiDemoPage> createState() =>
      _CustomFeedbackUiDemoPageState();
}

class _CustomFeedbackUiDemoPageState extends State<CustomFeedbackUiDemoPage> {
  late NiumaPlayerController _controller;

  // 切到坏 URL 的 toggle——演示 errorBuilder 触发条件
  bool _useBrokenSource = false;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    unawaited(_controller.initialize());
  }

  NiumaPlayerController _createController() {
    return NiumaPlayerController(
      NiumaMediaSource.single(
        NiumaDataSource.network(
          _useBrokenSource
              ? 'https://example.com/broken-non-existent.mp4'
              : 'https://artplayer.org/assets/sample/bbb-video.mp4',
        ),
      ),
      // 关掉 auto-failover，强制单线路失败 → phase=error → errorBuilder 兜
      options: const NiumaPlayerOptions(
        autoFailoverOnInitialError: false,
      ),
    );
  }

  Future<void> _swapSource() async {
    final old = _controller;
    setState(() {
      _useBrokenSource = !_useBrokenSource;
      _controller = _createController();
    });
    await old.dispose();
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
        title: const Text('自定义反馈 UI'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: NiumaPlayer(
                controller: _controller,
                // 自定义 loading：业务 logo + 进度文案
                loadingBuilder: (ctx) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF9F27),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '正在加载…',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                // 自定义 error：业务图标 + 解释文案 + 自家"重试"按钮
                errorBuilder: (ctx, err) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off,
                          color: Colors.white70, size: 56),
                      const SizedBox(height: 12),
                      Text(
                        '播放失败',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        err.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _controller.initialize(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新加载'),
                      ),
                    ],
                  ),
                ),
                // 自定义 ended：重播 + 业务 share / next
                endedBuilder: (ctx) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.replay_circle_filled,
                        color: Color(0xFFEF9F27), size: 56),
                    const SizedBox(height: 8),
                    const Text(
                      '播放完毕',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _controller.seekTo(Duration.zero);
                            await _controller.play();
                          },
                          icon: const Icon(Icons.replay),
                          label: const Text('重播'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('（业务 share 接入点）')),
                            );
                          },
                          icon: const Icon(Icons.share),
                          label: const Text('分享'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _swapSource,
                    icon: Icon(
                      _useBrokenSource
                          ? Icons.check_circle_outline
                          : Icons.bug_report_outlined,
                    ),
                    label: Text(
                      _useBrokenSource ? '切回好的源' : '切到坏的源（看 errorBuilder）',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _DocBlock(
                    title: 'loadingBuilder',
                    body:
                        'phase=opening / buffering 时渲染。默认 NiumaLoadingIndicator。',
                  ),
                  const SizedBox(height: 8),
                  const _DocBlock(
                    title: 'errorBuilder',
                    body: 'phase=error 时渲染。默认 NiumaErrorView 提供 onErrorRetry callback。',
                  ),
                  const SizedBox(height: 8),
                  const _DocBlock(
                    title: 'endedBuilder',
                    body: 'phase=ended 时渲染。默认 NiumaEndedView 提供 onEndedReplay callback。',
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
