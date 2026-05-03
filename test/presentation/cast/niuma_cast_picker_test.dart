import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/presentation/cast/niuma_cast_picker.dart';

import '../controls/fake_controller.dart';

class _FakeService extends CastService {
  _FakeService(this.protocolId, this.devices);
  @override
  final String protocolId;
  final List<CastDevice> devices;
  bool wasConnectCalled = false;
  CastDevice? lastConnected;
  @override
  Stream<List<CastDevice>> discover({Duration timeout = const Duration(seconds: 8)}) async* {
    yield devices;
  }
  @override
  Future<CastSession> connect(CastDevice d, NiumaPlayerController c) async {
    wasConnectCalled = true;
    lastConnected = d;
    throw UnimplementedError();  // 测试不需要真 session
  }
}

void main() {
  setUp(NiumaCastRegistry.debugClear);

  testWidgets('扫描出设备 → 列表显示', (tester) async {
    NiumaCastRegistry.register(_FakeService('dlna', const [
      CastDevice(id: 'a', name: '客厅电视', protocolId: 'dlna'),
      CastDevice(id: 'b', name: '卧室电视', protocolId: 'dlna'),
    ]));
    final ctl = FakeNiumaPlayerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(
          onPressed: () => NiumaCastPicker.show(ctx, ctl),
          child: const Text('open'),
        )),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('客厅电视'), findsOneWidget);
    expect(find.text('卧室电视'), findsOneWidget);
  });

  testWidgets('扫描 0 台 → 显示空状态', (tester) async {
    NiumaCastRegistry.register(_FakeService('dlna', const []));
    final ctl = FakeNiumaPlayerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (ctx) => ElevatedButton(
        onPressed: () => NiumaCastPicker.show(ctx, ctl),
        child: const Text('open'),
      ))),
    ));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(seconds: 9));  // 跨过 8s timeout
    expect(find.textContaining('未发现设备'), findsOneWidget);
  });

  testWidgets('点设备调 service.connect', (tester) async {
    final svc = _FakeService('dlna', const [
      CastDevice(id: 'a', name: '客厅电视', protocolId: 'dlna'),
    ]);
    NiumaCastRegistry.register(svc);
    final ctl = FakeNiumaPlayerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (ctx) => ElevatedButton(
        onPressed: () => NiumaCastPicker.show(ctx, ctl),
        child: const Text('open'),
      ))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('客厅电视'));
    await tester.pump();
    expect(svc.wasConnectCalled, isTrue);
    expect(svc.lastConnected?.id, 'a');
  });
}
