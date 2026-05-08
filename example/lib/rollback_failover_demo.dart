import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// 演示 SDK 默认开的两条 policy：
///
/// 1. **`autoFailoverOnInitialError`**：默认线路 `initialize` 失败时
///    自动按 `MediaLine.priority` 升序遍历下一条；全部失败 → `phase=error`。
/// 2. **`rollbackOnSwitchFailure`**：用户主动 `switchLine` 失败时静默回滚
///    到原线路，保留切换前的 position / wasPlaying。
///
/// 故意配三条线路：line1 / line2 是坏 URL，line3 是真能播的视频。
/// 默认行为：line1 fail → line2 fail → line3 success → 视频开始播放。
/// 业务侧 console 能看到两条 `LineSwitchFailed` 事件 + 一条 `LineSwitched(line3)`。
///
/// 主动切到 line1（坏的）：rollback 静默生效——视频继续放原来的（line3），
/// console 看到 `LineSwitchFailed`，但 `await switchLine()` 不抛错。
class RollbackFailoverDemoPage extends StatefulWidget {
  const RollbackFailoverDemoPage({super.key});

  @override
  State<RollbackFailoverDemoPage> createState() =>
      _RollbackFailoverDemoPageState();
}

class _RollbackFailoverDemoPageState extends State<RollbackFailoverDemoPage> {
  late final NiumaPlayerController _controller;
  StreamSubscription<NiumaPlayerEvent>? _eventSub;
  final List<String> _eventLog = <String>[];

  @override
  void initState() {
    super.initState();
    _controller = NiumaPlayerController(
      NiumaMediaSource.lines(
        lines: [
          // priority 升序遍历——0 最高，先试。前两条故意是坏的。
          MediaLine(
            id: 'broken_404',
            label: '坏线路一（404）',
            priority: 0,
            source: NiumaDataSource.network(
              'https://example.com/this-url-does-not-exist.mp4',
            ),
          ),
          MediaLine(
            id: 'broken_codec',
            label: '坏线路二（无效格式）',
            priority: 1,
            source: NiumaDataSource.network(
              'https://httpstat.us/200?sleep=200',
            ),
          ),
          MediaLine(
            id: 'good',
            label: '好线路',
            priority: 2,
            source: NiumaDataSource.network(
              'https://artplayer.org/assets/sample/bbb-video.mp4',
            ),
          ),
        ],
        defaultLineId: 'broken_404',
      ),
      // 默认两条 policy 都是 true，这里写出来给业务方对照——可以关掉
      // 让 SDK 退到旧行为。
      options: const NiumaPlayerOptions(
        autoFailoverOnInitialError: true,
        rollbackOnSwitchFailure: true,
      ),
    );
    _eventSub = _controller.events.listen((e) {
      if (!mounted) return;
      setState(() {
        _eventLog.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)}  $e');
        if (_eventLog.length > 30) _eventLog.removeLast();
      });
    });
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
    } catch (e) {
      // 全部线路失败时 initialize() rethrow——controller phase 同时翻
      // error，errorBuilder 会兜住 UI。
      debugPrint('initialize 全失败：$e');
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _switchToBroken() async {
    // 用户故意切坏线路——预期：switchLine 内部 rollback 到 'good'，
    // 视频不中断，console 只多一条 LineSwitchFailed 事件。await 不抛错。
    await _controller.switchLine('broken_404');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('失败回滚 + 自动 failover'),
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: NiumaPlayer(
              controller: _controller,
              onErrorRetry: () => _controller.initialize(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _switchToBroken,
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('切到坏线路（看 rollback）'),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '事件日志（最新在上）：',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _eventLog.length,
              itemBuilder: (ctx, i) => Text(
                _eventLog[i],
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
