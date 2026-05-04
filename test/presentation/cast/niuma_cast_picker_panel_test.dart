import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/presentation/cast/niuma_cast_picker_panel.dart';

import '../controls/fake_controller.dart';

void main() {
  testWidgets('panel 显示「视频暂停中」+「选择投屏设备」', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: NiumaCastPickerPanel(
            controller: ctl,
            onClose: () {},
            devices: const [],
            isScanning: false,
            onSelectDevice: (_) async {},
            onRefresh: () {},
          ),
        ),
      ),
    ));
    expect(find.text('视频暂停中'), findsOneWidget);
    expect(find.text('选择投屏设备'), findsOneWidget);
  });

  testWidgets('显示 N 台设备时 list 渲染对应数量 device-item', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: NiumaCastPickerPanel(
            controller: ctl,
            onClose: () {},
            devices: const [
              CastDevice(
                id: 'dlna:uuid:abc-123',
                name: '客厅小米电视',
                protocolId: 'dlna',
              ),
              CastDevice(
                id: 'airplay:Apple-TV-XYZ',
                name: '卧室 Apple TV',
                protocolId: 'airplay',
              ),
            ],
            isScanning: false,
            onSelectDevice: (_) async {},
            onRefresh: () {},
          ),
        ),
      ),
    ));
    expect(find.text('已搜索到 2 台设备'), findsOneWidget);
    expect(find.text('客厅小米电视'), findsOneWidget);
    expect(find.text('卧室 Apple TV'), findsOneWidget);
  });

  testWidgets('点击 X 触发 onClose', (t) async {
    bool closed = false;
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: NiumaCastPickerPanel(
            controller: ctl,
            onClose: () => closed = true,
            devices: const [],
            isScanning: false,
            onSelectDevice: (_) async {},
            onRefresh: () {},
          ),
        ),
      ),
    ));
    await t.tap(find.byKey(const Key('cast-panel-close')));
    expect(closed, isTrue);
  });

  testWidgets('connectedDeviceId 匹配设备时高亮显示「已连接」', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: NiumaCastPickerPanel(
            controller: ctl,
            onClose: () {},
            devices: const [
              CastDevice(
                id: 'tv1',
                name: '客厅小米电视',
                protocolId: 'dlna',
              ),
            ],
            isScanning: false,
            connectedDeviceId: 'tv1',
            onSelectDevice: (_) async {},
            onRefresh: () {},
          ),
        ),
      ),
    ));
    expect(find.text('已连接 · DLNA'), findsOneWidget);
  });

  testWidgets('isScanning=true 时显示「搜索中...」', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: NiumaCastPickerPanel(
            controller: ctl,
            onClose: () {},
            devices: const [],
            isScanning: true,
            onSelectDevice: (_) async {},
            onRefresh: () {},
          ),
        ),
      ),
    ));
    expect(find.text('搜索中...'), findsOneWidget);
  });
}
