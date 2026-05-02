import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

import 'controls/fake_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 拦截 SystemChrome 调用——录下 method 名 + arg 供断言用。
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

  testWidgets('NiumaShortVideoFullscreenPage.route 返回 PageRouteBuilder',
      (tester) async {
    final ctl = FakeNiumaPlayerController();
    final route = NiumaShortVideoFullscreenPage.route(controller: ctl);
    expect(route, isA<PageRouteBuilder<void>>());
  });

  testWidgets(
      'initState 调 SystemChrome.setPreferredOrientations(landscape)',
      (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx).push(
              NiumaShortVideoFullscreenPage.route(controller: ctl),
            ),
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
            onPressed: () => Navigator.of(ctx).push(
              NiumaShortVideoFullscreenPage.route(controller: ctl),
            ),
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

  testWidgets('dispose 双步骤：先 portrait 再空 list + edgeToEdge', (tester) async {
    final ctl = FakeNiumaPlayerController();

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx).push(
              NiumaShortVideoFullscreenPage.route(controller: ctl),
            ),
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
    // dispose 触发两次 setPreferredOrientations：
    // 第 1 次：[DeviceOrientation.portraitUp]——触发 Android Activity reconfigure
    // 第 2 次：空 list（post-frame）——释放锁定
    expect(orientationCalls.length, greaterThanOrEqualTo(2),
        reason: 'dispose 触发两次：portrait → empty');
    expect(orientationCalls.first.arguments,
        equals(<String>['DeviceOrientation.portraitUp']),
        reason: 'dispose 第一步：强设 portrait 触发 Activity reconfigure');
    expect(orientationCalls.last.arguments, isEmpty,
        reason: 'dispose 最后一步（post-frame）：空 list 释放锁定');

    final modeCalls = calls
        .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
        .toList();
    expect(modeCalls, isNotEmpty);
    expect(modeCalls.last.arguments, 'SystemUiMode.edgeToEdge');
  });

  testWidgets('页面包含同一个 controller 的 NiumaShortVideoPlayer', (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx).push(
              NiumaShortVideoFullscreenPage.route(controller: ctl),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final players = tester.widgetList<NiumaShortVideoPlayer>(
        find.byType(NiumaShortVideoPlayer));
    expect(players, isNotEmpty);
    expect(players.first.controller, same(ctl));
  });

  testWidgets('页面默认包含 NiumaShortVideoFullscreenButton（leftCenterBuilder 槽）',
      (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx).push(
              NiumaShortVideoFullscreenPage.route(controller: ctl),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(NiumaShortVideoFullscreenPage),
        matching: find.byType(NiumaShortVideoFullscreenButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets('NiumaShortVideoFullscreenPage 背景为黑色 Scaffold', (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx).push(
              NiumaShortVideoFullscreenPage.route(controller: ctl),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(NiumaShortVideoFullscreenPage),
        matching: find.byType(Scaffold),
      ),
    );
    expect(scaffold.backgroundColor, Colors.black);
  });
}
