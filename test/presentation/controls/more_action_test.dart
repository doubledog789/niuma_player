import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/more_action.dart';

void main() {
  testWidgets('MoreAction 点击触发 onTap，回传 context', (t) async {
    BuildContext? capturedCtx;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: MoreAction(onTap: (ctx) => capturedCtx = ctx)),
    ));
    await t.tap(find.byType(MoreAction));
    expect(capturedCtx, isNotNull);
  });
}
