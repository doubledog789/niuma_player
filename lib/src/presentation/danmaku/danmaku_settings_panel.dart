import 'package:flutter/material.dart';

import 'package:niuma_player/src/presentation/danmaku/niuma_danmaku_controller.dart';

/// 弹幕设置面板：3 个 slider（fontScale / opacity / displayAreaPercent）+ Switch。
///
/// 不强制 modal——业务可以 `showModalBottomSheet`（推荐）也可以塞 Drawer / Dialog。
/// 直接修改传入的 [NiumaDanmakuController]。
class DanmakuSettingsPanel extends StatelessWidget {
  /// 构造一个 panel。
  const DanmakuSettingsPanel({super.key, required this.danmaku});

  /// 被驱动的 controller。
  final NiumaDanmakuController danmaku;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: danmaku,
      builder: (ctx, _) {
        final s = danmaku.settings;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('显示弹幕'),
                value: s.visible,
                onChanged: (v) =>
                    danmaku.updateSettings(s.copyWith(visible: v)),
              ),
              _SliderRow(
                label: '字号',
                sliderKey: const Key('danmaku-font-scale-slider'),
                value: s.fontScale,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                onChanged: (v) =>
                    danmaku.updateSettings(s.copyWith(fontScale: v)),
              ),
              _SliderRow(
                label: '不透明度',
                sliderKey: const Key('danmaku-opacity-slider'),
                value: s.opacity,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                onChanged: (v) =>
                    danmaku.updateSettings(s.copyWith(opacity: v)),
              ),
              _SliderRow(
                label: '显示区域',
                sliderKey: const Key('danmaku-area-slider'),
                value: s.displayAreaPercent,
                min: 0.25,
                max: 1.0,
                divisions: 3,
                onChanged: (v) =>
                    danmaku.updateSettings(s.copyWith(displayAreaPercent: v)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.sliderKey,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });
  final String label;
  final Key sliderKey;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        Expanded(
          child: Slider(
            key: sliderKey,
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 50, child: Text(value.toStringAsFixed(2))),
      ],
    );
  }
}
