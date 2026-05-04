import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

import '../../_helpers/svg_finder.dart';
import 'fake_controller.dart';

void main() {
  testWidgets('source.lines.length == 1 时不渲染', (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: QualitySelector(controller: ctl))),
    ));

    // length == 1 → SizedBox.shrink，没有图标。
    expect(findNiumaIcon(NiumaSdkAssets.icQuality), findsNothing);
  });

  testWidgets('source.lines.length > 1 时渲染并展开 popup', (tester) async {
    final source = NiumaMediaSource.lines(
      defaultLineId: 'sd',
      lines: [
        MediaLine(
          id: 'sd',
          label: '480P',
          source: NiumaDataSource.network('https://x.com/sd.m3u8'),
        ),
        MediaLine(
          id: 'hd',
          label: '720P',
          source: NiumaDataSource.network('https://x.com/hd.m3u8'),
        ),
      ],
    );
    final ctl = FakeNiumaPlayerController(source: source);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: QualitySelector(controller: ctl))),
    ));

    expect(findNiumaIcon(NiumaSdkAssets.icQuality), findsOneWidget);

    await tester.tap(find.byType(QualitySelector));
    await tester.pumpAndSettle();

    expect(find.text('480P'), findsOneWidget);
    expect(find.text('720P'), findsOneWidget);
  });

  testWidgets('选中线路调 controller.switchLine(id)', (tester) async {
    final source = NiumaMediaSource.lines(
      defaultLineId: 'sd',
      lines: [
        MediaLine(
          id: 'sd',
          label: '480P',
          source: NiumaDataSource.network('https://x.com/sd.m3u8'),
        ),
        MediaLine(
          id: 'hd',
          label: '720P',
          source: NiumaDataSource.network('https://x.com/hd.m3u8'),
        ),
      ],
    );
    final ctl = FakeNiumaPlayerController(source: source);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: QualitySelector(controller: ctl))),
    ));

    await tester.tap(find.byType(QualitySelector));
    await tester.pumpAndSettle();

    await tester.tap(find.text('720P'));
    await tester.pumpAndSettle();

    expect(ctl.lastSwitchLineId, 'hd');
  });
}
