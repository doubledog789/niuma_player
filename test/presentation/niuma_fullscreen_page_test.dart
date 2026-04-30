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

  testWidgets('dispose 双步骤：先 portrait 再空 list + edgeToEdge', (tester) async {
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
    // dispose 触发两次 setPreferredOrientations：
    // 第 1 次：[DeviceOrientation.portraitUp]——同步触发 Android Activity
    //         从横屏切回竖屏 reconfigure。不传这个的话，Android 即使解锁
    //         也停在横屏 config，体感"退全屏没回正"。
    // 第 2 次：空 list（在 post-frame callback 里）——释放锁定，让用户
    //         后续能按传感器自由旋转。
    // calls.clear 在 pop 之前调过，所以这里只有 dispose 引发的 2 次调用：
    //   第 1 次：[DeviceOrientation.portraitUp]——同步触发 Android Activity
    //          从横屏切回竖屏 reconfigure。不传这个的话，Android 即使解锁
    //          也停在横屏 config，体感"退全屏没回正"。
    //   第 2 次：空 list（在 post-frame callback 里）——释放锁定，让用户
    //          后续能按传感器自由旋转。
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
