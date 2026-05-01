import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
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

    video.setPosition(const Duration(seconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    video.setPosition(const Duration(seconds: 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(NiumaDanmakuOverlay), findsOneWidget);
    expect(calls, isNotEmpty);
    danmaku.dispose();
  });

  testWidgets('overlay tap 穿透到下方 GestureDetector', (tester) async {
    final video = FakeNiumaPlayerController();
    final danmaku = NiumaDanmakuController();
    var underlyingTapped = 0;

    await tester.pumpWidget(MaterialApp(
      home: Stack(
        fit: StackFit.expand,
        children: [
          // 底层 click-catcher（NiumaPlayer 中那个）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => underlyingTapped++,
          ),
          // overlay 在上层
          NiumaDanmakuOverlay(video: video, danmaku: danmaku),
        ],
      ),
    ));
    await tester.pump();
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    expect(underlyingTapped, 1,
        reason: 'overlay 必须 IgnorePointer 让 tap 穿透到下方 click-catcher');
    danmaku.dispose();
  });
}
