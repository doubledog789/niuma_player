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
  testWidgets('bili 预设：顶栏 back/title/more + 中央 + 底栏 lineSwitch + 进度条', (t) async {
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
            onMore: (_) {},
          ),
        ),
      ),
    ));
    expect(find.byType(BackAction), findsOneWidget);
    expect(find.byType(TitleBar), findsOneWidget);
    expect(find.byType(MoreAction), findsOneWidget);
    expect(find.byType(CastAction), findsNothing); // cast/pip 现在通过 more 菜单触发
    expect(find.byType(PipAction), findsNothing);
    expect(find.byType(LineSwitchPill), findsOneWidget); // 在底栏
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
            onMore: (_) {},
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
            onMore: (_) {},
          ),
        ),
      ),
    ));
    expect(find.text('actions-marker'), findsOneWidget);
  });

  testWidgets('more 按钮在全屏顶栏中贴近右边界', (t) async {
    final ctl = FakeNiumaPlayerController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 400,
          child: BiliStyleControlBar(
            controller: ctl,
            config: NiumaControlBarConfig.bili,
            title: '一个比较长的标题，验证右侧 more 不会被标题布局拖离右边',
            subtitle: '副标题',
            onBack: () {},
            onMore: (_) {},
          ),
        ),
      ),
    ));

    final moreRight = t.getTopRight(find.byType(MoreAction)).dx;
    // 800 屏宽 - Container right padding 12 = 788：MoreAction 右边贴
    // Container 右内边。阈值 786 给 ±2 容错（IconButton 内 padding 等）。
    expect(moreRight, greaterThanOrEqualTo(786));
  });

  testWidgets('buttonOverrides BuilderOverride 完全替换 more 按钮', (t) async {
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
              NiumaControlButton.more:
                  ButtonOverride.builder((_) => const Text('custom-more')),
            },
            onBack: () {},
            onCast: () {},
            onPip: () {},
            onMore: (_) {},
          ),
        ),
      ),
    ));
    expect(find.text('custom-more'), findsOneWidget);
    expect(find.byType(MoreAction), findsNothing);
  });

  testWidgets('buttonOverrides FieldsOverride 替换 lineSwitch 字段且 onTap 可点击',
      (t) async {
    final ctl = FakeNiumaPlayerController(
      source: NiumaMediaSource.lines(
        lines: [
          MediaLine(
            id: 'high',
            label: 'HD',
            source: NiumaDataSource.network('https://x/h.mp4'),
          ),
        ],
        defaultLineId: 'high',
      ),
    );
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
              NiumaControlButton.lineSwitch: ButtonOverride.fields(
                icon: const Icon(Icons.flutter_dash),
                label: '自定义线路',
                onTap: () => tapped = true,
              ),
            },
            onBack: () {},
            onCast: () {},
            onPip: () {},
            onMore: (_) {},
          ),
        ),
      ),
    ));
    expect(find.text('自定义线路'), findsOneWidget);
    expect(find.byIcon(Icons.flutter_dash), findsOneWidget);
    await t.tap(find.text('自定义线路'));
    expect(tapped, isTrue);
  });
}
