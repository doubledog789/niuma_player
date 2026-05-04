import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/icon_label_action.dart';

void main() {
  testWidgets('IconLabelAction 渲染 icon + label 垂直布局', (t) async {
    bool tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IconLabelAction(
          icon: const Icon(Icons.cast),
          label: '投屏',
          onTap: () => tapped = true,
        ),
      ),
    ));
    expect(find.byIcon(Icons.cast), findsOneWidget);
    expect(find.text('投屏'), findsOneWidget);
    await t.tap(find.byType(IconLabelAction));
    expect(tapped, isTrue);
  });

  testWidgets('IconLabelAction enabled=false 时点击不触发 onTap', (t) async {
    bool tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IconLabelAction(
          icon: const Icon(Icons.cast),
          label: '投屏',
          onTap: () => tapped = true,
          enabled: false,
        ),
      ),
    ));
    expect(
      find.descendant(
          of: find.byType(IconLabelAction),
          matching: find.byType(IgnorePointer)),
      findsOneWidget,
    );
    await t.tap(find.byType(IconLabelAction), warnIfMissed: false);
    expect(tapped, isFalse);
  });
}
