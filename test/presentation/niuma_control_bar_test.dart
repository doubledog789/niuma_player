import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

import 'controls/fake_controller.dart';

void main() {
  testWidgets(
      '宽度 <420（PiP 迷你窗）→ 只渲染 ScrubBar，藏 Row 避免 RenderFlex overflow',
      (tester) async {
    final ctl = FakeNiumaPlayerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240, // 模拟 Android PiP 迷你窗
          height: 135,
          child: NiumaControlBar(controller: ctl),
        ),
      ),
    ));

    expect(find.byType(ScrubBar), findsOneWidget,
        reason: '窄宽下 ScrubBar 仍渲染（只有一根条不会 overflow）');
    expect(find.byType(PlayPauseButton), findsNothing,
        reason: '窄宽下 Row 整体不渲染——8 按钮 + Spacer 塞不下');
    expect(find.byType(FullscreenButton), findsNothing);
    // 关键：不应该有 RenderFlex overflow assertion 抛出。
    expect(tester.takeException(), isNull);
  });

  testWidgets('NiumaControlBar 包含 ScrubBar + 全部 9 个原子控件', (tester) async {
    final ctl = FakeNiumaPlayerController(
      source: NiumaMediaSource.lines(
        lines: [
          MediaLine(
            id: 'high',
            label: 'HD',
            source: NiumaDataSource.network('https://example.com/high.mp4'),
          ),
          MediaLine(
            id: 'low',
            label: 'SD',
            source: NiumaDataSource.network('https://example.com/low.mp4'),
          ),
        ],
        defaultLineId: 'high',
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 200,
          child: NiumaControlBar(controller: ctl),
        ),
      ),
    ));

    expect(find.byType(ScrubBar), findsOneWidget);
    expect(find.byType(PlayPauseButton), findsOneWidget);
    expect(find.byType(TimeDisplay), findsOneWidget);
    expect(find.byType(DanmakuButton), findsOneWidget);
    expect(find.byType(SubtitleButton), findsOneWidget);
    expect(find.byType(SpeedSelector), findsOneWidget);
    expect(find.byType(QualitySelector), findsOneWidget);
    expect(find.byType(VolumeButton), findsOneWidget);
    expect(find.byType(FullscreenButton), findsOneWidget);
  });

  testWidgets('ScrubBar 在 Row 上方（垂直方向 ScrubBar.center.dy < Row.center.dy）',
      (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 200,
          child: NiumaControlBar(controller: ctl),
        ),
      ),
    ));

    final scrubCenter = tester.getCenter(find.byType(ScrubBar));
    final rowCenter = tester.getCenter(find.byType(PlayPauseButton));
    expect(scrubCenter.dy, lessThan(rowCenter.dy),
        reason: 'ScrubBar 应该垂直在 Row of buttons 上方');
  });

  testWidgets('M9 disabled 控件（DanmakuButton/SubtitleButton）存在但不响应点击',
      (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 200,
          child: NiumaControlBar(controller: ctl),
        ),
      ),
    ));

    // disabled 控件被 IgnorePointer 包住——通过查找 IgnorePointer 祖先验证。
    final danmakuIgnore = find.ancestor(
      of: find.byType(DanmakuButton),
      matching: find.byType(IgnorePointer),
    );
    final subtitleIgnore = find.ancestor(
      of: find.byType(SubtitleButton),
      matching: find.byType(IgnorePointer),
    );
    expect(danmakuIgnore, findsWidgets);
    expect(subtitleIgnore, findsWidgets);
  });

  testWidgets('NiumaControlBar 背景使用主题 controlsBackgroundGradient',
      (tester) async {
    final ctl = FakeNiumaPlayerController();
    const customGradient = [Color(0xFF112233), Color(0xFF445566)];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaPlayerThemeData(
          data: const NiumaPlayerTheme(
            controlsBackgroundGradient: customGradient,
          ),
          child: SizedBox(
            width: 800,
            height: 200,
            child: NiumaControlBar(controller: ctl),
          ),
        ),
      ),
    ));

    // 找到 NiumaControlBar 内部的 Container，并验证 decoration.gradient.colors。
    final container = tester
        .widgetList<Container>(find.descendant(
          of: find.byType(NiumaControlBar),
          matching: find.byType(Container),
        ))
        .firstWhere(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).gradient is LinearGradient,
        );
    final dec = container.decoration as BoxDecoration;
    final grad = dec.gradient as LinearGradient;
    expect(grad.colors, customGradient);
  });
}
