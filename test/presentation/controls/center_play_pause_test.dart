import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/niuma_sdk_assets.dart';
import 'package:niuma_player/src/presentation/controls/center_play_pause.dart';

import '../../_helpers/svg_finder.dart';
import 'fake_controller.dart';

void main() {
  testWidgets('暂停态 + visible=true 时渲染中央按钮', (t) async {
    final ctl = FakeNiumaPlayerController()..isPlaying = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CenterPlayPause(controller: ctl, visible: true),
      ),
    ));
    expect(findNiumaIcon(NiumaSdkAssets.icPlay), findsOneWidget);
  });

  testWidgets('播放态时不渲染', (t) async {
    final ctl = FakeNiumaPlayerController()..isPlaying = true;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CenterPlayPause(controller: ctl, visible: true),
      ),
    ));
    expect(findNiumaIcon(NiumaSdkAssets.icPlay), findsNothing);
  });

  testWidgets('暂停 + visible=false 时不渲染', (t) async {
    final ctl = FakeNiumaPlayerController()..isPlaying = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CenterPlayPause(controller: ctl, visible: false),
      ),
    ));
    expect(findNiumaIcon(NiumaSdkAssets.icPlay), findsNothing);
  });
}
