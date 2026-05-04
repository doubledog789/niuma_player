import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/back_action.dart';

void main() {
  testWidgets('BackAction 点击触发 onBack', (t) async {
    bool back = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BackAction(onBack: () => back = true),
      ),
    ));
    await t.tap(find.byType(BackAction));
    expect(back, isTrue);
  });
}
