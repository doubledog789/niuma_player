import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

import '../controls/fake_controller.dart';

void main() {
  testWidgets('投屏中视频区中央显示 "投屏中" 与设备名', (tester) async {
    final ctl = FakeNiumaPlayerController();
    ctl.debugSetCastSession(_FakeSession('客厅小米电视'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NiumaPlayer(controller: ctl)),
    ));
    expect(find.textContaining('客厅小米电视'), findsWidgets);
    expect(find.text('投屏中'), findsOneWidget);
  });

  testWidgets('castSession=null 时不显示覆盖层', (tester) async {
    final ctl = FakeNiumaPlayerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NiumaPlayer(controller: ctl)),
    ));
    expect(find.text('投屏中'), findsNothing);
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
