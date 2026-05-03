import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

import '../controls/fake_controller.dart';

void main() {
  testWidgets('castSession=null → 显示 cast 图标 outlined', (tester) async {
    final ctl = FakeNiumaPlayerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NiumaCastButton(controller: ctl)),
    ));
    expect(find.byIcon(Icons.cast), findsOneWidget);
    expect(find.byIcon(Icons.cast_connected), findsNothing);
  });

  testWidgets('castSession 非 null → 显示 cast_connected 图标 + 设备名', (tester) async {
    final ctl = FakeNiumaPlayerController();
    ctl.debugSetCastSession(_FakeSession('客厅小米电视'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NiumaCastButton(controller: ctl)),
    ));
    expect(find.byIcon(Icons.cast_connected), findsOneWidget);
    expect(find.text('客厅小米电视'), findsOneWidget);
  });
}

class _FakeSession implements CastSession {
  _FakeSession(this.deviceName);
  final String deviceName;
  @override
  CastDevice get device => CastDevice(id: 'x', name: deviceName, protocolId: 'dlna');
  @override
  ValueListenable<CastConnectionState> get state =>
      ValueNotifier(CastConnectionState.connected);
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration p) async {}
  @override
  Future<Duration> getPosition() async => Duration.zero;
  @override
  Future<void> disconnect() async {}
}
