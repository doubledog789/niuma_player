import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/control_bar/niuma_control_bar_config.dart';
import 'package:niuma_player/src/presentation/control_bar/niuma_control_button.dart';

void main() {
  test('minimal 预设：顶左 [back, title]，底左 [playPause]，底右 [fullscreen]', () {
    const c = NiumaControlBarConfig.minimal;
    expect(c.topLeading, [
      NiumaControlButton.back,
      NiumaControlButton.title,
    ]);
    expect(c.topActions, isEmpty);
    expect(c.bottomLeft, [NiumaControlButton.playPause]);
    expect(c.bottomRight, [NiumaControlButton.fullscreen]);
    expect(c.centerPlayPause, isFalse);
    expect(c.showProgressBar, isTrue);
  });

  test('bili 预设：顶栏 [back, title] + [more] / 底栏 [playPause+弹幕] / 中央按钮启用', () {
    const c = NiumaControlBarConfig.bili;
    expect(c.topLeading, [
      NiumaControlButton.back,
      NiumaControlButton.title,
    ]);
    expect(c.topActions, [NiumaControlButton.more]);
    expect(c.bottomLeft, [
      NiumaControlButton.playPause,
      NiumaControlButton.danmakuToggle,
      NiumaControlButton.danmakuInput,
    ]);
    expect(c.bottomRight, [
      NiumaControlButton.speed,
      NiumaControlButton.lineSwitch,
    ]);
    expect(c.centerPlayPause, isTrue);
    expect(c.showProgressBar, isTrue);
  });

  test('full 预设：所有按钮全开', () {
    const c = NiumaControlBarConfig.full;
    expect(c.bottomRight, contains(NiumaControlButton.subtitle));
    expect(c.bottomRight, contains(NiumaControlButton.volume));
    expect(c.bottomRight, contains(NiumaControlButton.danmakuToggle));
    expect(c.bottomRight, contains(NiumaControlButton.danmakuInput));
    expect(c.centerPlayPause, isTrue);
  });

  test('自定义 config 字段保留', () {
    const c = NiumaControlBarConfig(
      topActions: [NiumaControlButton.cast],
      bottomLeft: [NiumaControlButton.playPause],
      centerPlayPause: true,
    );
    expect(c.topActions, [NiumaControlButton.cast]);
    expect(c.centerPlayPause, isTrue);
  });

  test('NiumaControlBarConfig 两个相同实例相等', () {
    const a = NiumaControlBarConfig.minimal;
    const b = NiumaControlBarConfig.minimal;
    expect(a, equals(b));
  });
}
