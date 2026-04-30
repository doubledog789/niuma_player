import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

import 'controls/fake_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 拦截 SystemChrome 调用——`SystemChannels.platform` 上的 method call
  /// 是 SystemChrome 的物理通道，把它录下来后可以验证 method 名 + arg。
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('NiumaFullscreenPage.route 返回 PageRouteBuilder', (tester) async {
    final ctl = FakeNiumaPlayerController();
    final route = NiumaFullscreenPage.route(controller: ctl);
    expect(route, isA<PageRouteBuilder<void>>());
  });

  testWidgets('initState 调 SystemChrome.setPreferredOrientations(landscape)',
      (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      navigatorKey: GlobalKey<NavigatorState>(),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () {
              Navigator.of(ctx).push(
                NiumaFullscreenPage.route(controller: ctl),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    ));

    calls.clear();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final orientationCalls = calls
        .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
        .toList();
    expect(orientationCalls, isNotEmpty,
        reason: 'initState 应当调用 setPreferredOrientations');
    final args = orientationCalls.first.arguments as List<dynamic>;
    expect(
      args,
      containsAll(<String>[
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]),
    );
  });

  testWidgets(
      'initState 调 SystemChrome.setEnabledSystemUIMode(immersiveSticky)',
      (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx)
                .push(NiumaFullscreenPage.route(controller: ctl)),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    calls.clear();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final modeCalls = calls
        .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
        .toList();
    expect(modeCalls, isNotEmpty,
        reason: 'initState 应当调用 setEnabledSystemUIMode');
    expect(modeCalls.first.arguments, 'SystemUiMode.immersiveSticky');
  });

  testWidgets('dispose 释放 orientation 锁（空 list）+ edgeToEdge', (tester) async {
    final ctl = FakeNiumaPlayerController();

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx)
                .push(NiumaFullscreenPage.route(controller: ctl)),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    calls.clear();
    navKey.currentState!.pop();
    await tester.pumpAndSettle();

    final orientationCalls = calls
        .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
        .toList();
    expect(orientationCalls, isNotEmpty,
        reason: 'dispose 应当再次调用 setPreferredOrientations 恢复');
    // 恢复时传空 list——告诉 Flutter "释放锁定，回到 OS / app 默认
    // 方向"。如果传 DeviceOrientation.values（4 个全开），Android 会
    // 解读成 SCREEN_ORIENTATION_FULL_USER 显式锁定，Activity 不重新
    // 评估当前方向，用户感觉"无法旋转"。
    final args = orientationCalls.last.arguments as List<dynamic>;
    expect(args, isEmpty,
        reason: 'dispose 必须传空 list 释放方向锁，否则 Android 仍处显式锁定状态');

    final modeCalls = calls
        .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
        .toList();
    expect(modeCalls, isNotEmpty);
    expect(modeCalls.last.arguments, 'SystemUiMode.edgeToEdge');
  });

  testWidgets('页面包含同一个 controller 的 NiumaPlayer', (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx)
                .push(NiumaFullscreenPage.route(controller: ctl)),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final players = tester.widgetList<NiumaPlayer>(find.byType(NiumaPlayer));
    expect(players, isNotEmpty);
    expect(players.first.controller, same(ctl));
  });

  testWidgets('NiumaFullscreenPage 背景为黑色 Scaffold', (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx)
                .push(NiumaFullscreenPage.route(controller: ctl)),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(NiumaFullscreenPage),
        matching: find.byType(Scaffold),
      ),
    );
    expect(scaffold.backgroundColor, Colors.black);
  });
}
