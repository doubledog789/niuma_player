import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/scrub_bar.dart';

import 'fake_controller.dart';

void main() {
  testWidgets('ScrubBar 不传 chapters 时不渲染 chapter mark', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: ScrubBar(controller: ctl)),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('scrub-chapter-mark')), findsNothing);
    await ctl.dispose();
  });

  testWidgets('ScrubBar 传 chapters 时按 list.length 渲染对应数量 mark', (t) async {
    final ctl = FakeNiumaPlayerController();
    // 设置 duration 让进度条可计算位置
    ctl.value = ctl.value.copyWith(
      duration: const Duration(seconds: 120),
      position: Duration.zero,
    );
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScrubBar(
          controller: ctl,
          chapters: const [
            Duration(seconds: 25),
            Duration(seconds: 55),
            Duration(seconds: 80),
          ],
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('scrub-chapter-mark')), findsNWidgets(3));
    await ctl.dispose();
  });
}
