import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/niuma_control_button.dart';

void main() {
  test('NiumaControlButton 枚举包含 17 个原子按钮（M16+lock/settings）', () {
    final values = NiumaControlButton.values;
    expect(values.length, 17);
    expect(
        values,
        containsAll(<NiumaControlButton>[
          NiumaControlButton.back,
          NiumaControlButton.title,
          NiumaControlButton.cast,
          NiumaControlButton.pip,
          NiumaControlButton.lineSwitch,
          NiumaControlButton.more,
          NiumaControlButton.playPause,
          NiumaControlButton.speed,
          NiumaControlButton.danmakuToggle,
          NiumaControlButton.danmakuInput,
          NiumaControlButton.subtitle,
          NiumaControlButton.volume,
          NiumaControlButton.fullscreen,
          NiumaControlButton.timeDisplay,
          NiumaControlButton.scrubBar,
          NiumaControlButton.lock,
          NiumaControlButton.settings,
        ]));
  });
}
