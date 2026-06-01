import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player_example/niuma_ui/niuma_ui.dart';

void main() {
  testWidgets('volume HUD 显示 hudIcon + label + 进度条', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: NiumaGestureHud(
          state: GestureFeedbackState(
            kind: GestureKind.volume,
            progress: 0.6,
            label: '60%',
            hudIcon: GestureHudIcon.volume,
          ),
        ),
      ),
    ));
    expect(
      find.byWidgetPredicate(
        (w) => w is NiumaSdkIcon && w.asset == NiumaUiAssets.icVolume,
      ),
      findsOneWidget,
    );
    expect(find.text('60%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('seek HUD 拆 label 成 delta + target + total 三部分', (tester) async {
    // 抖音风设计：label 按 ' / ' 拆三段，分别用不同字号 / 颜色渲染：
    // - delta `+15s`：brand 橙色小字 + 方向箭头
    // - target `1:23`：白色超大字（30pt）
    // - total `/ 4:56`：白色 dim 小字
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: NiumaGestureHud(
          state: GestureFeedbackState(
            kind: GestureKind.horizontalSeek,
            progress: 0.5,
            label: '+15s / 1:23 / 4:56',
          ),
        ),
      ),
    ));
    expect(find.text('+15s'), findsOneWidget);
    expect(find.text('1:23'), findsOneWidget);
    expect(find.text('/ 4:56'), findsOneWidget);
    // delta 是 forward → 渲染 fast_forward 箭头
    expect(find.byIcon(Icons.fast_forward), findsOneWidget);
    // 进度条仍然渲染（视觉锚点）
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('seek HUD 反向（-10s）渲染 fast_rewind 箭头', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: NiumaGestureHud(
          state: GestureFeedbackState(
            kind: GestureKind.horizontalSeek,
            progress: 0.2,
            label: '-10s / 0:30 / 4:56',
          ),
        ),
      ),
    ));
    expect(find.text('-10s'), findsOneWidget);
    expect(find.text('0:30'), findsOneWidget);
    expect(find.byIcon(Icons.fast_rewind), findsOneWidget);
    expect(find.byIcon(Icons.fast_forward), findsNothing);
  });

  testWidgets('label = null 时不渲染文字', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: NiumaGestureHud(
          state: GestureFeedbackState(
            kind: GestureKind.doubleTap,
            progress: 1.0,
          ),
        ),
      ),
    ));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('icon = null 时不渲染图标', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: NiumaGestureHud(
          state: GestureFeedbackState(
            kind: GestureKind.brightness,
            progress: 0.5,
            label: '50%',
          ),
        ),
      ),
    ));
    expect(find.byType(Icon), findsNothing);
    expect(find.text('50%'), findsOneWidget);
  });
}
