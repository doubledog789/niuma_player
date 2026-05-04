import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/scrub_bar.dart';

import 'fake_controller.dart';

/// Returns a [Finder] that matches Positioned widgets whose key is a
/// [ValueKey<String>] starting with 'scrub-chapter-mark-'.
Finder _chapterMarkFinder() => find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> && k.value.startsWith('scrub-chapter-mark-');
    });

void main() {
  testWidgets('ScrubBar 不传 chapters 时不渲染 chapter mark', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: ScrubBar(controller: ctl)),
    ));
    await t.pumpAndSettle();
    expect(_chapterMarkFinder(), findsNothing);
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
    expect(_chapterMarkFinder(), findsNWidgets(3));
    await ctl.dispose();
  });
}
