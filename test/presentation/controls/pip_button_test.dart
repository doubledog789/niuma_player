import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

import 'fake_controller.dart';

void main() {
  testWidgets('isPictureInPictureSupported=false → IgnorePointer ignoring=true',
      (tester) async {
    final c = FakeNiumaPlayerController();
    // 默认 supported=false（NiumaPlayerValue.uninitialized() 默认值）
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PipButton(controller: c)),
    ));
    final ip = find.descendant(
      of: find.byType(PipButton),
      matching: find.byWidgetPredicate(
        (w) => w is IgnorePointer && w.ignoring == true,
      ),
    );
    expect(ip, findsOneWidget);
  });

  testWidgets('supported + 不在 PiP → outline 图标，tap 调 enterPip',
      (tester) async {
    final c = FakeNiumaPlayerController();
    c.value = c.value.copyWith(
      isPictureInPictureSupported: true,
      isInPictureInPicture: false,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PipButton(controller: c)),
    ));
    expect(find.byIcon(Icons.picture_in_picture_alt_outlined), findsOneWidget);
    expect(c.enterPictureInPictureCalled, 0);
    await tester.tap(find.byType(PipButton));
    await tester.pump();
    expect(c.enterPictureInPictureCalled, 1);
  });

  testWidgets('supported + 在 PiP → 高亮 alt 图标，tap 调 exitPip',
      (tester) async {
    final c = FakeNiumaPlayerController();
    c.value = c.value.copyWith(
      isPictureInPictureSupported: true,
      isInPictureInPicture: true,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PipButton(controller: c)),
    ));
    expect(find.byIcon(Icons.picture_in_picture_alt), findsOneWidget);
    await tester.tap(find.byType(PipButton));
    await tester.pump();
    expect(c.exitPictureInPictureCalled, 1);
  });

  testWidgets('controller.value 变化时 button 自动重建', (tester) async {
    final c = FakeNiumaPlayerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PipButton(controller: c)),
    ));
    // 初始 supported=false → IgnorePointer
    expect(
      find.descendant(
        of: find.byType(PipButton),
        matching: find.byWidgetPredicate(
          (w) => w is IgnorePointer && w.ignoring == true,
        ),
      ),
      findsOneWidget,
    );
    // 翻 supported=true → 普通态
    c.value = c.value.copyWith(isPictureInPictureSupported: true);
    await tester.pump();
    expect(find.byIcon(Icons.picture_in_picture_alt_outlined), findsOneWidget);
  });
}
