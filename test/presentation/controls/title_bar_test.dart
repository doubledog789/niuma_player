import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/title_bar.dart';

void main() {
  testWidgets('TitleBar 渲染 title + subtitle', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Row(children: [TitleBar(title: '视频标题', subtitle: '副标题 · P1')]),
      ),
    ));
    expect(find.text('视频标题'), findsOneWidget);
    expect(find.text('副标题 · P1'), findsOneWidget);
  });

  testWidgets('TitleBar 没传 subtitle 时只渲染 title', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Row(children: [TitleBar(title: '视频标题')]),
      ),
    ));
    expect(find.text('视频标题'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });
}
