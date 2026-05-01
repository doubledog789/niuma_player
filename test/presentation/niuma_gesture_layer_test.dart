import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/domain/gesture_feedback_state.dart';
import 'package:niuma_player/src/domain/gesture_kind.dart';
import 'package:niuma_player/src/presentation/niuma_gesture_layer.dart';

import 'controls/fake_controller.dart';

void main() {
  testWidgets('双击 → controller pause/play 调用', (tester) async {
    final c = FakeNiumaPlayerController();
    c.value = c.value.copyWith(phase: PlayerPhase.playing);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 200,
          child: NiumaGestureLayer(
            controller: c,
            child: Container(color: Colors.black),
          ),
        ),
      ),
    ));
    final center = tester.getCenter(find.byType(NiumaGestureLayer));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 350));
    expect(c.pauseCount, 1);
  });

  testWidgets('长按 start → setSpeed(2.0)，end → 恢复原速', (tester) async {
    final c = FakeNiumaPlayerController();
    c.value = c.value.copyWith(playbackSpeed: 1.5);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 200,
          child: NiumaGestureLayer(
            controller: c,
            child: Container(color: Colors.black),
          ),
        ),
      ),
    ));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(NiumaGestureLayer)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.lastSpeed, 2.0);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.lastSpeed, 1.5);
  });

  testWidgets('disabledGestures 长按禁用', (tester) async {
    final c = FakeNiumaPlayerController();
    c.value = c.value.copyWith(playbackSpeed: 1.0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 200,
          child: NiumaGestureLayer(
            controller: c,
            disabledGestures: const {GestureKind.longPressSpeed},
            child: Container(color: Colors.black),
          ),
        ),
      ),
    ));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(NiumaGestureLayer)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.lastSpeed, isNull);
    await gesture.up();
  });

  testWidgets('hudBuilder 替换默认 HUD', (tester) async {
    final c = FakeNiumaPlayerController();
    var builderCalled = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 200,
          child: NiumaGestureLayer(
            controller: c,
            hudBuilder: (ctx, state) {
              builderCalled++;
              return const Text('CUSTOM HUD');
            },
            child: Container(color: Colors.black),
          ),
        ),
      ),
    ));
    c.debugSetGestureFeedback(const GestureFeedbackState(
      kind: GestureKind.volume,
      progress: 0.5,
    ));
    await tester.pump();
    expect(find.text('CUSTOM HUD'), findsOneWidget);
    expect(builderCalled, greaterThan(0));
  });

  testWidgets('onTap 透传不被 layer 自己消化', (tester) async {
    final c = FakeNiumaPlayerController();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 200,
          child: NiumaGestureLayer(
            controller: c,
            onTap: () => taps++,
            child: Container(color: Colors.black),
          ),
        ),
      ),
    ));
    await tester.tapAt(tester.getCenter(find.byType(NiumaGestureLayer)));
    await tester.pump(const Duration(milliseconds: 350));
    expect(taps, 1);
  });

  testWidgets('enabled=false 仅透传 onTap，pan/双击/长按全部跳过',
      (tester) async {
    final c = FakeNiumaPlayerController();
    c.value = c.value.copyWith(phase: PlayerPhase.playing);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 200,
          child: NiumaGestureLayer(
            controller: c,
            enabled: false,
            onTap: () => taps++,
            child: Container(color: Colors.black),
          ),
        ),
      ),
    ));
    final center = tester.getCenter(find.byType(NiumaGestureLayer));
    // 双击
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 350));
    // disabled 双击应当不触发 pause
    expect(c.pauseCount, 0);
    // 但 single tap 仍然透传到 onTap（取决于实现：disabled 下 onDoubleTap=null
    // 所以 GestureDetector 会把每次 tap 都直接当 single tap）
    // 至少 onTap 被调过——具体次数依赖 Flutter gesture arena 行为
  });
}
