import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/presentation/niuma_fullscreen_page.dart'
    show NiumaFullscreenScope;

import 'controls/fake_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('不在 fullscreen scope 时显示 Icons.fullscreen', (tester) async {
    final c = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaShortVideoFullscreenButton(controller: c),
      ),
    ));

    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit), findsNothing);
  });

  testWidgets('在 M9 NiumaFullscreenScope 内显示 Icons.fullscreen_exit',
      (tester) async {
    final c = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NiumaFullscreenScope(
          child: NiumaShortVideoFullscreenButton(controller: c),
        ),
      ),
    ));

    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen), findsNothing);
  });

  testWidgets('不在 scope 时点击 push 一个新 route', (tester) async {
    final c = FakeNiumaPlayerController();
    final pushedRoutes = <Route<dynamic>>[];

    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [
        _RecordingObserver(pushedRoutes),
      ],
      home: Scaffold(
        body: NiumaShortVideoFullscreenButton(controller: c),
      ),
    ));

    final before = pushedRoutes.length;
    await tester.tap(find.byType(NiumaShortVideoFullscreenButton));
    await tester.pump();

    expect(pushedRoutes.length, greaterThan(before));
  });

  testWidgets('在 M9 NiumaFullscreenScope 内点击 pop（退回上一 route）',
      (tester) async {
    final c = FakeNiumaPlayerController();
    final navKey = GlobalKey<NavigatorState>();

    // 先 push 一个空 route，再在其上展示 scope+button
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: NiumaFullscreenScope(
                    child: NiumaShortVideoFullscreenButton(controller: c),
                  ),
                ),
              ),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // 当前在第二层 route，maybePop 理应 pop 掉它
    expect(navKey.currentState!.canPop(), isTrue);
    await tester.tap(find.byType(NiumaShortVideoFullscreenButton));
    await tester.pumpAndSettle();

    // 退回到第一层（找回 TextButton）
    expect(find.text('go'), findsOneWidget);
  });
}

class _RecordingObserver extends NavigatorObserver {
  _RecordingObserver(this._routes);
  final List<Route<dynamic>> _routes;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }
}
