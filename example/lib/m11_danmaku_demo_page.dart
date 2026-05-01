import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// M11 demo：用 mock loader 喂 1000 条样本弹幕，演示三模式 + lazy load + 设置。
class M11DanmakuDemoPage extends StatefulWidget {
  /// 创建一个 [M11DanmakuDemoPage]。
  const M11DanmakuDemoPage({super.key});
  @override
  State<M11DanmakuDemoPage> createState() => _M11DanmakuDemoPageState();
}

class _M11DanmakuDemoPageState extends State<M11DanmakuDemoPage> {
  late final NiumaPlayerController _video;
  late final NiumaDanmakuController _danmaku;
  final _random = math.Random(42);
  Timer? _autoInjectTimer;

  @override
  void initState() {
    super.initState();
    _video = NiumaPlayerController.dataSource(
      NiumaDataSource.network(
        'https://artplayer.org/assets/sample/bbb-video.mp4',
      ),
    );
    _danmaku = NiumaDanmakuController(loader: _mockLoader);
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await _video.initialize();
      if (!mounted) return;
      await _video.play();
      // 自动每 2.5s 注入一条新弹幕，让全屏页也能看到 add() 路径在跑
      _autoInjectTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        if (!mounted) return;
        _injectNow();
      });
    } catch (e) {
      debugPrint('init 失败：$e');
    }
  }

  /// 每个 60s 桶生成 100 条随机弹幕（混三模式）。
  FutureOr<List<DanmakuItem>> _mockLoader(Duration s, Duration e) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return List.generate(100, (i) {
      final ms = s.inMilliseconds +
          _random.nextInt(e.inMilliseconds - s.inMilliseconds);
      final mode = DanmakuMode.values[_random.nextInt(3)];
      return DanmakuItem(
        position: Duration(milliseconds: ms),
        text: '弹幕 ${s.inSeconds}+$i',
        fontSize: 18 + _random.nextInt(8).toDouble(),
        color: Color(0xFF000000 | _random.nextInt(0xFFFFFF))
            .withValues(alpha: 1),
        mode: mode,
      );
    });
  }

  void _injectNow() {
    final mode = DanmakuMode.values[_random.nextInt(3)];
    _danmaku.add(DanmakuItem(
      position: _video.value.position,
      text: '我刚发的：${DateTime.now().millisecondsSinceEpoch % 10000}',
      color: const Color(0xFFFF8800),
      mode: mode,
    ));
  }

  @override
  void dispose() {
    _autoInjectTimer?.cancel();
    unawaited(_video.dispose());
    _danmaku.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('M11 弹幕 demo'),
        actions: [
          IconButton(
            tooltip: '设置面板',
            icon: const Icon(Icons.tune),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => DanmakuSettingsPanel(danmaku: _danmaku),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: NiumaPlayer(
                  controller: _video,
                  danmakuController: _danmaku,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: _injectNow,
                    child: const Text('插一条 echo 弹幕（mock send）'),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '验证清单：\n'
                '1. 启动后弹幕按 60s 桶按需 lazy load（mock 100 条/桶）\n'
                '2. 三模式同屏：scroll / topFixed / bottomFixed\n'
                '3. 滚动平滑（60fps，不跳跃）——Ticker 内插位置\n'
                '4. tap 视频区切换控件显隐——overlay 不阻挡 hit test\n'
                '5. 进度条 seek → 弹幕清空重算\n'
                '6. 暂停 → 弹幕画面冻结（Ticker 停）\n'
                '7. 顶栏齿轮：字号 / 不透明度 / 显示区域 / ON/OFF\n'
                '8. 控件条 DanmakuButton 也能 toggle 开关\n'
                '9. 「插一条 echo」按钮模拟 send 后回包\n'
                '10. 全屏后弹幕仍在飞 + 每 2.5s 自动加一条橙色弹幕（验证 add 在全屏内有效）',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
