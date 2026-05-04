import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
// NiumaFullscreenScope 是内部 InheritedWidget marker——不在公开 API 中
// 暴露，但单测需要直接构造它来模拟"当前是否在全屏页内"的两种分支。
import 'package:niuma_player/src/presentation/niuma_fullscreen_page.dart'
    show NiumaFullscreenScope;

import '../../_helpers/svg_finder.dart';
import 'fake_controller.dart';

void main() {
  testWidgets('点击触发 Navigator.push——push 一个新 route', (tester) async {
    final ctl = FakeNiumaPlayerController();
    final navObserver = _RecordingNavigatorObserver();

    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [navObserver],
      home: Scaffold(body: FullscreenButton(controller: ctl)),
    ));

    expect(findNiumaIcon(NiumaSdkAssets.icFullscreenEnter), findsOneWidget);

    await tester.tap(find.byType(FullscreenButton));
    await tester.pumpAndSettle();

    // 至少有一次 didPush（除了初始 home route）。
    expect(navObserver.pushedRoutes, isNotEmpty,
        reason: '点击 FullscreenButton 应当 push 新 route');
  });

  testWidgets('NiumaFullscreenScope 缺席的子 route 不被误判为"在全屏内"',
      (tester) async {
    // 模拟 example demo 页：home push 一个非 fullscreen 的 demo route，
    // demo 里挂 FullscreenButton。早先的 `!isFirst` fallback 会把这个
    // demo 页误判为"在全屏内"，导致按钮变成 pop（demo 页被关闭）。
    final ctl = FakeNiumaPlayerController();
    final navObserver = _RecordingNavigatorObserver();

    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [navObserver],
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () {
              Navigator.of(ctx).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      Scaffold(body: FullscreenButton(controller: ctl)),
                ),
              );
            },
            child: const Text('go-demo'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go-demo'));
    await tester.pumpAndSettle();
    navObserver.pushedRoutes.clear();

    // demo 页不在全屏内 → icon 应是 fullscreen（不是 fullscreen_exit）。
    expect(findNiumaIcon(NiumaSdkAssets.icFullscreenEnter), findsOneWidget,
        reason: 'demo 子 route 没有 NiumaFullscreenScope，应显示进入图标');

    // 点击应当 push 新 route（进入全屏），而不是 pop。
    await tester.tap(findNiumaIcon(NiumaSdkAssets.icFullscreenEnter));
    await tester.pumpAndSettle();
    expect(navObserver.pushedRoutes, isNotEmpty,
        reason: '没有 NiumaFullscreenScope 的子 route 点击应 push，不是 pop');
  });

  testWidgets('NiumaFullscreenScope 包裹时 icon=fullscreen_exit 且点击 pop',
      (tester) async {
    final ctl = FakeNiumaPlayerController();
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () {
              Navigator.of(ctx).push<void>(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    body: NiumaFullscreenScope(
                      child: FullscreenButton(controller: ctl),
                    ),
                  ),
                ),
              );
            },
            child: const Text('go-fs'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go-fs'));
    await tester.pumpAndSettle();

    // 子 route 包裹了 NiumaFullscreenScope → icon = fullscreen_exit。
    expect(findNiumaIcon(NiumaSdkAssets.icFullscreenExit), findsOneWidget);

    // 点击应 pop——回到 home（找回 'go-fs' 文本）。
    await tester.tap(findNiumaIcon(NiumaSdkAssets.icFullscreenExit));
    await tester.pumpAndSettle();
    expect(find.text('go-fs'), findsOneWidget,
        reason: '点击应 pop 回 home，而不是再 push 一层全屏');
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
