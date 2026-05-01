import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/danmaku_models.dart';
import 'package:niuma_player/src/presentation/danmaku_settings_panel.dart';
import 'package:niuma_player/src/presentation/niuma_danmaku_controller.dart';

void main() {
  testWidgets('Switch toggle 改 settings.visible', (tester) async {
    final c = NiumaDanmakuController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DanmakuSettingsPanel(danmaku: c)),
    ));
    expect(c.settings.visible, isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(c.settings.visible, isFalse);
    c.dispose();
  });

  testWidgets('opacity slider 调用 updateSettings', (tester) async {
    final c = NiumaDanmakuController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DanmakuSettingsPanel(danmaku: c)),
    ));
    final slider = find.byKey(const Key('danmaku-opacity-slider'));
    expect(slider, findsOneWidget);
    // 拖到接近左端
    await tester.drag(slider, const Offset(-200, 0));
    await tester.pump();
    expect(c.settings.opacity, lessThan(1.0));
    c.dispose();
  });

  testWidgets('panel 监听 controller 重建', (tester) async {
    final c = NiumaDanmakuController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DanmakuSettingsPanel(danmaku: c)),
    ));
    c.updateSettings(c.settings.copyWith(opacity: 0.3));
    await tester.pump();
    final slider = tester.widget<Slider>(
        find.byKey(const Key('danmaku-opacity-slider')));
    expect(slider.value, closeTo(0.3, 0.001));
    c.dispose();
  });
}
