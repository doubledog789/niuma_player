import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/presentation/controls/back_action.dart';
import 'package:niuma_player/src/presentation/controls/cast_action.dart';
import 'package:niuma_player/src/presentation/controls/center_play_pause.dart';
import 'package:niuma_player/src/presentation/controls/line_switch_pill.dart';
import 'package:niuma_player/src/presentation/controls/more_action.dart';
import 'package:niuma_player/src/presentation/controls/pip_action.dart';
import 'package:niuma_player/src/presentation/controls/title_bar.dart';

import 'controls/fake_controller.dart';

void main() {
  testWidgets('bili 预设：渲染顶栏 6 项 + 中央 + 底栏 + 进度条', (t) async {
    final ctl = FakeNiumaPlayerController(
      source: NiumaMediaSource.lines(
        lines: [
          MediaLine(
            id: 'high',
            label: 'HD',
            source: NiumaDataSource.network('https://x/h.mp4'),
          ),
          MediaLine(
            id: 'low',
            label: 'SD',
            source: NiumaDataSource.network('https://x/l.mp4'),
          ),
        ],
        defaultLineId: 'high',
      ),
    );
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: BiliStyleControlBar(
            controller: ctl,
            config: NiumaControlBarConfig.bili,
            title: '视频标题',
            subtitle: '副标题',
            onBack: () {},
            onCast: () {},
            onPip: () {},
            onMore: () {},
          ),
        ),
      ),
    ));
    expect(find.byType(BackAction), findsOneWidget);
    expect(find.byType(TitleBar), findsOneWidget);
    expect(find.byType(CastAction), findsOneWidget);
    expect(find.byType(PipAction), findsOneWidget);
    expect(find.byType(LineSwitchPill), findsOneWidget);
    expect(find.byType(MoreAction), findsOneWidget);
    // CenterPlayPause: bili 预设 centerPlayPause=true，不论暂停态都会构造（暂停态才显示）
    expect(find.byType(CenterPlayPause), findsOneWidget);
    expect(find.byType(ScrubBar), findsOneWidget);
  });

  testWidgets('minimal 预设：不渲染 cast/pip/more', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: BiliStyleControlBar(
            controller: ctl,
            config: NiumaControlBarConfig.minimal,
            title: '视频',
            onBack: () {},
          ),
        ),
      ),
    ));
    expect(find.byType(CastAction), findsNothing);
    expect(find.byType(PipAction), findsNothing);
    expect(find.byType(MoreAction), findsNothing);
    expect(find.byType(BackAction), findsOneWidget);
  });

  testWidgets('rightRailBuilder 提供时渲染右侧 rail', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: BiliStyleControlBar(
            controller: ctl,
            config: NiumaControlBarConfig.bili,
            title: '视频',
            rightRailBuilder: (_) => const Text('rail-marker'),
            onBack: () {},
            onCast: () {},
            onPip: () {},
            onMore: () {},
          ),
        ),
      ),
    ));
    expect(find.text('rail-marker'), findsOneWidget);
  });

  testWidgets('actionsBuilder 在 topActions enum 之后追加', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: BiliStyleControlBar(
            controller: ctl,
            config: NiumaControlBarConfig.bili,
            title: '视频',
            actionsBuilder: (_) => const Text('actions-marker'),
            onBack: () {},
            onCast: () {},
            onPip: () {},
            onMore: () {},
          ),
        ),
      ),
    ));
    expect(find.text('actions-marker'), findsOneWidget);
  });

  testWidgets('buttonOverrides BuilderOverride 完全替换 cast 按钮', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: BiliStyleControlBar(
            controller: ctl,
            config: NiumaControlBarConfig.bili,
            title: '视频',
            buttonOverrides: {
              NiumaControlButton.cast:
                  ButtonOverride.builder((_) => const Text('custom-cast')),
            },
            onBack: () {},
            onCast: () {},
            onPip: () {},
            onMore: () {},
          ),
        ),
      ),
    ));
    expect(find.text('custom-cast'), findsOneWidget);
    expect(find.byType(CastAction), findsNothing);
  });

  testWidgets('buttonOverrides FieldsOverride 替换 cast 字段且 onTap 可点击',
      (t) async {
    final ctl = FakeNiumaPlayerController();
    bool tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: BiliStyleControlBar(
            controller: ctl,
            config: NiumaControlBarConfig.bili,
            title: '视频',
            buttonOverrides: {
              NiumaControlButton.cast: ButtonOverride.fields(
                icon: const Icon(Icons.flutter_dash),
                label: '自定义投屏',
                onTap: () => tapped = true,
              ),
            },
            onBack: () {},
            onCast: () {},
            onPip: () {},
            onMore: () {},
          ),
        ),
      ),
    ));
    expect(find.text('自定义投屏'), findsOneWidget);
    expect(find.byIcon(Icons.flutter_dash), findsOneWidget);
    await t.tap(find.text('自定义投屏'));
    expect(tapped, isTrue);
  });
}
