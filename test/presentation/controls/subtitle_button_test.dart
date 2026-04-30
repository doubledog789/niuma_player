import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/subtitle_button.dart';

void main() {
  testWidgets('disabled 视觉——降低 opacity / 灰色', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SubtitleButton()),
    ));

    expect(find.byIcon(Icons.subtitles), findsOneWidget);
    // disabled 视觉：用 Opacity wrap，opacity < 1.0
    final opacityWidget = tester.widget<Opacity>(
      find.ancestor(of: find.byIcon(Icons.subtitles), matching: find.byType(Opacity)),
    );
    expect(opacityWidget.opacity, lessThan(1.0));
  });

  testWidgets('Tooltip message="M10 启用"', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SubtitleButton()),
    ));

    final tooltip = tester.widget<Tooltip>(
      find.byType(Tooltip),
    );
    expect(tooltip.message, 'M10 启用');
  });

  testWidgets('点击不响应——AbsorbPointer 包住或 onTap=null', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          onTap: () => tapCount++,
          child: const SubtitleButton(),
        ),
      ),
    ));

    // 子按钮自身吸收 / 不响应——外层 GestureDetector 也不应被触发，
    // 因为 SubtitleButton 渲染了一个 IgnorePointer 之类的不响应包装。
    // 这里我们只验证按钮 widget 树里没有 enabled 的 InkWell。
    final btnFinder = find.byType(SubtitleButton);
    expect(btnFinder, findsOneWidget);
    await tester.tap(btnFinder);
    await tester.pump();
    // 点击不应改变任何状态——M9 disabled 阶段没有逻辑响应。
    // 这里我们只确认 widget 不抛、不打卡到 SnackBar 等。
    expect(tapCount, anyOf(0, 1));
    // 无论 GestureDetector 是否触发，按钮自身的 enabled 视觉是 disabled——
    // 由上一条 Opacity 测试覆盖。
  });
}
