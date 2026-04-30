import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/fullscreen_button.dart';

import 'fake_controller.dart';

void main() {
  testWidgets('点击触发 Navigator.push——push 一个新 route', (tester) async {
    final ctl = FakeNiumaPlayerController();
    final navObserver = _RecordingNavigatorObserver();

    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [navObserver],
      home: Scaffold(body: FullscreenButton(controller: ctl)),
    ));

    expect(find.byIcon(Icons.fullscreen), findsOneWidget);

    await tester.tap(find.byType(FullscreenButton));
    await tester.pumpAndSettle();

    // 至少有一次 didPush（除了初始 home route）。
    expect(navObserver.pushedRoutes, isNotEmpty,
        reason: '点击 FullscreenButton 应当 push 新 route');
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    // 跳过 MaterialApp home route（previousRoute == null）。
    if (previousRoute != null) {
      pushedRoutes.add(route);
    }
  }
}
