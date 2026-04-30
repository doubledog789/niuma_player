import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

import 'fake_controller.dart';

/// 受控替身：把 thumbnailFor 接到测试可控的 frame 上。
class _StubThumbController extends FakeNiumaPlayerController {
  _StubThumbController({super.source});

  ThumbnailFrame? frameToReturn;

  @override
  ThumbnailFrame? thumbnailFor(Duration position) => frameToReturn;
}

NiumaPlayerValue _vAt({
  required Duration position,
  Duration duration = const Duration(seconds: 100),
  Duration buffered = const Duration(seconds: 0),
  PlayerPhase phase = PlayerPhase.playing,
}) =>
    NiumaPlayerValue.uninitialized().copyWith(
      phase: phase,
      position: position,
      duration: duration,
      bufferedPosition: buffered,
    );

void main() {
  group('ScrubBar 渲染', () {
    testWidgets('显示当前 controller.value.position 对应的 thumb',
        (tester) async {
      final ctl = _StubThumbController();
      ctl.value = _vAt(position: const Duration(seconds: 25));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 60,
            child: ScrubBar(controller: ctl),
          ),
        ),
      ));
      // CustomPaint 子节点存在即视为渲染了进度条。
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('ScrubBar 拖动交互', () {
    testWidgets('pointer down 进入 scrubbing 状态——thumbnailVtt 非 null 时 preview 出现',
        (tester) async {
      final ctl = _StubThumbController(
        source: NiumaMediaSource.single(
          NiumaDataSource.network('https://example.com/v.mp4'),
          thumbnailVtt: 'https://example.com/thumbs.vtt',
        ),
      );
      ctl.value = _vAt(position: const Duration(seconds: 10));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 200,
                height: 60,
                child: ScrubBar(controller: ctl),
              ),
            ),
          ),
        ),
      ));

      // 静止状态：preview 不应渲染。
      expect(find.byType(NiumaScrubPreview), findsNothing);

      // 在 ScrubBar 中点按下。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ScrubBar)),
      );
      await tester.pump();

      expect(find.byType(NiumaScrubPreview), findsOneWidget);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('thumbnailVtt == null 时 preview 永不渲染',
        (tester) async {
      final ctl = _StubThumbController();
      // source 默认无 thumbnailVtt
      ctl.value = _vAt(position: const Duration(seconds: 10));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 60,
            child: ScrubBar(controller: ctl),
          ),
        ),
      ));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ScrubBar)),
      );
      await tester.pump();

      expect(find.byType(NiumaScrubPreview), findsNothing);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('pointer up 调 controller.seekTo 到对应位置', (tester) async {
      final ctl = _StubThumbController();
      ctl.value = _vAt(
        position: Duration.zero,
        duration: const Duration(seconds: 100),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 60,
            child: ScrubBar(controller: ctl),
          ),
        ),
      ));

      // 在中间点按下并松开——25% 到 75% 之间应当 seek 到接近 mid 处。
      final mid = tester.getCenter(find.byType(ScrubBar));
      final gesture = await tester.startGesture(mid);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(ctl.lastSeek, isNotNull);
      // ScrubBar 占满 200 宽，duration=100s，按下点在中间 → 大概 50s
      expect(ctl.lastSeek!.inSeconds, inInclusiveRange(40, 60));
    });

    testWidgets('pointer move 更新 scrubMs（commit 后 seek 到 move 的位置）',
        (tester) async {
      final ctl = _StubThumbController();
      ctl.value = _vAt(
        position: Duration.zero,
        duration: const Duration(seconds: 100),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 60,
            child: ScrubBar(controller: ctl),
          ),
        ),
      ));

      final origin = tester.getTopLeft(find.byType(ScrubBar));
      // 起点：x=10（5%），移到 x=180（90%）。
      final gesture = await tester.startGesture(
        Offset(origin.dx + 10, origin.dy + 30),
      );
      await tester.pump();
      await gesture.moveTo(Offset(origin.dx + 180, origin.dy + 30));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(ctl.lastSeek, isNotNull);
      // 期望大约 90s（180/200 * 100 = 90）
      expect(ctl.lastSeek!.inSeconds, inInclusiveRange(80, 95));
    });
  });
}
