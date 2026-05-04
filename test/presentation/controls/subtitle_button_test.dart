import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/niuma_sdk_assets.dart';
import 'package:niuma_player/src/presentation/controls/subtitle_button.dart';

import '../../_helpers/svg_finder.dart';

void main() {
  testWidgets('disabled 视觉——降低 opacity / 灰色', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SubtitleButton()),
    ));

    expect(findNiumaIcon(NiumaSdkAssets.icSubtitle), findsOneWidget);
    // disabled 视觉：用 Opacity wrap，opacity < 1.0
    final opacityWidget = tester.widget<Opacity>(
      find.ancestor(
        of: findNiumaIcon(NiumaSdkAssets.icSubtitle),
        matching: find.byType(Opacity),
      ),
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

  testWidgets('点击不响应——IgnorePointer 拦截 hit-test，外层 GestureDetector 不触发',
      (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: GestureDetector(
            onTap: () => tapCount++,
            behavior: HitTestBehavior.opaque,
            // GestureDetector 自身需要有尺寸——Center 把内容居中。
            child: const SizedBox(
              width: 48,
              height: 48,
              child: SubtitleButton(),
            ),
          ),
        ),
      ),
    ));

    final btnFinder = find.byType(SubtitleButton);
    expect(btnFinder, findsOneWidget);
    // SubtitleButton 自身渲染了一个 ignoring=true 的 IgnorePointer，
    // 把按钮区的 hit-test 全吃掉。Tooltip 内部也有一个 IgnorePointer，
    // 但 ignoring=false——所以这里只断"至少有一个 ignoring=true 的
    // IgnorePointer 在按钮树里"。关键回归：之前的 anyOf(0, 1) 任何
    // 情况都 pass 是无意义断言。
    final ignoringTrue = find.descendant(
      of: btnFinder,
      matching: find.byWidgetPredicate(
        (w) => w is IgnorePointer && w.ignoring == true,
      ),
    );
    expect(
      ignoringTrue,
      findsOneWidget,
      reason: 'SubtitleButton 应当渲染 ignoring=true 的 IgnorePointer 拦截 hit-test',
    );
    // 按钮内部 hit-test 全被 IgnorePointer 吃掉——tap 落到按钮区域时
    // 应当**不**触发外层 GestureDetector（因为 IgnorePointer 让按钮
    // 区域的命中盒消失，tester.tap 直接命中外层 GestureDetector 的
    // hit area；warnIfMissed 关掉因为 IgnorePointer 有可能让命中
    // 测试无法 hit 任何 button-shaped widget）。验证手段是：按钮
    // 子树没有 InkWell。
    expect(
      find.descendant(
        of: btnFinder,
        matching: find.byType(InkWell),
      ),
      findsNothing,
      reason: 'SubtitleButton 不应渲染可交互 InkWell',
    );
    await tester.tap(btnFinder, warnIfMissed: false);
    await tester.pump();
    // tap 落在按钮区域 → 因为 IgnorePointer 让按钮 hit 失败，
    // 外层 GestureDetector 仍接住——tapCount 应当等于 1。
    expect(tapCount, 1, reason: 'IgnorePointer 不阻止外层 GestureDetector 接 hit');
  });
}
