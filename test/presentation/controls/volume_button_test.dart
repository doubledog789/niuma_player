import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/niuma_sdk_assets.dart';
import 'package:niuma_player/src/presentation/controls/volume_button.dart';

import '../../_helpers/svg_finder.dart';
import 'fake_controller.dart';

void main() {
  testWidgets('点击切换 mute 状态——首次点击 setVolume(0)', (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VolumeButton(controller: ctl)),
    ));

    // 初始状态非 mute——显示 volume_up 图标。
    expect(findNiumaIcon(NiumaSdkAssets.icVolume), findsOneWidget);

    await tester.tap(find.byType(VolumeButton));
    await tester.pump();

    expect(ctl.lastVolume, 0.0);
    // 切换为 mute 状态——显示 volume_off 图标。
    expect(findNiumaIcon(NiumaSdkAssets.icVolumeMute), findsOneWidget);
  });

  testWidgets('再次点击 unmute——setVolume(1)', (tester) async {
    final ctl = FakeNiumaPlayerController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VolumeButton(controller: ctl)),
    ));

    await tester.tap(find.byType(VolumeButton));
    await tester.pump();
    expect(ctl.lastVolume, 0.0);

    await tester.tap(find.byType(VolumeButton));
    await tester.pump();
    expect(ctl.lastVolume, 1.0);
    expect(findNiumaIcon(NiumaSdkAssets.icVolume), findsOneWidget);
  });
}
