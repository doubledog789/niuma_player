import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/presentation/controls/line_switch_pill.dart';

import 'fake_controller.dart';

void main() {
  testWidgets('多 line 时渲染当前 line label', (t) async {
    final ctl = FakeNiumaPlayerController(
      source: NiumaMediaSource.lines(
        lines: [
          MediaLine(
            id: 'high',
            label: 'HD',
            source: NiumaDataSource.network('https://x.example.com/h.mp4'),
          ),
          MediaLine(
            id: 'low',
            label: 'SD',
            source: NiumaDataSource.network('https://x.example.com/l.mp4'),
          ),
        ],
        defaultLineId: 'high',
      ),
    );
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: LineSwitchPill(controller: ctl)),
    ));
    expect(find.text('HD'), findsOneWidget);
  });

  testWidgets('单 line 时整个 widget 不渲染任何 line label 文字（SizedBox.shrink）', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: LineSwitchPill(controller: ctl)),
    ));
    // 单 line 整个 widget 不渲染任何 line label 文字
    expect(find.byType(LineSwitchPill), findsOneWidget);
    expect(find.text('HD'), findsNothing);
    expect(find.text('default'), findsNothing);
  });
}
