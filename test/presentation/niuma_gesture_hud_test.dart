import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/gesture_feedback_state.dart';
import 'package:niuma_player/src/domain/gesture_kind.dart';
import 'package:niuma_player/src/presentation/niuma_gesture_hud.dart';

void main() {
  testWidgets('volume HUD 显示 icon + label + 进度条', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: NiumaGestureHud(
          state: GestureFeedbackState(
            kind: GestureKind.volume,
            progress: 0.6,
            label: '60%',
            icon: Icons.volume_up,
          ),
        ),
      ),
    ));
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('seek HUD 显示 label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: NiumaGestureHud(
          state: GestureFeedbackState(
            kind: GestureKind.horizontalSeek,
            progress: 0.5,
            label: '+15s / 1:23 / 4:56',
            icon: Icons.fast_forward,
          ),
        ),
      ),
    ));
    expect(find.text('+15s / 1:23 / 4:56'), findsOneWidget);
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
