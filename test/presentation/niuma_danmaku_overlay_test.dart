import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/danmaku_models.dart';
import 'package:niuma_player/src/presentation/niuma_danmaku_controller.dart';
import 'package:niuma_player/src/presentation/niuma_danmaku_overlay.dart';

import 'controls/fake_controller.dart';

void main() {
  testWidgets('挂载 + 销毁不挂', (tester) async {
    final video = FakeNiumaPlayerController();
    final danmaku = NiumaDanmakuController()
      ..add(const DanmakuItem(position: Duration(seconds: 1), text: '666'));

    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 360,
        height: 200,
        child: NiumaDanmakuOverlay(video: video, danmaku: danmaku),
      ),
    ));
    await tester.pump();
    expect(find.byType(NiumaDanmakuOverlay), findsOneWidget);
    danmaku.dispose();
  });

  testWidgets('settings.visible=false 时返回 SizedBox.expand 不画 paint',
      (tester) async {
    final video = FakeNiumaPlayerController();
    final danmaku = NiumaDanmakuController(
      initial: const DanmakuSettings(visible: false),
    );

    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 360,
        height: 200,
        child: NiumaDanmakuOverlay(video: video, danmaku: danmaku),
      ),
    ));
    await tester.pump();
    // visible=false 时 build 走的是 SizedBox.expand 分支，不挂 CustomPaint
    expect(
      find.descendant(
        of: find.byType(NiumaDanmakuOverlay),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
      reason: 'visible=false 时应走 SizedBox.expand 不渲染 painter',
    );
    danmaku.dispose();
  });

  testWidgets('seek 大幅跳变触发 lazy load + 挂载稳定', (tester) async {
    final video = FakeNiumaPlayerController();
    final calls = <(Duration, Duration)>[];
    final danmaku = NiumaDanmakuController(
      loader: (s, e) {
        calls.add((s, e));
        return <DanmakuItem>[];
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 360,
        height: 200,
        child: NiumaDanmakuOverlay(video: video, danmaku: danmaku),
      ),
    ));

    // 初始 position 0，跳到 100s（>1s 阈值）→ 触发 ensureLoadedFor
    video.setPosition(const Duration(seconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 再跳回 5s
    video.setPosition(const Duration(seconds: 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(NiumaDanmakuOverlay), findsOneWidget);
    // 至少触发过 1 次 loader（跨桶 / 大幅 seek 都会触发）
    expect(calls, isNotEmpty);
    danmaku.dispose();
  });
}
