import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/danmaku_toggle.dart';

void main() {
  testWidgets('点击切换 ValueNotifier', (t) async {
    final n = ValueNotifier<bool>(false);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: DanmakuToggle(visibility: n)),
    ));
    expect(n.value, isFalse);
    await t.tap(find.byType(DanmakuToggle));
    await t.pump();
    expect(n.value, isTrue);
  });
}
