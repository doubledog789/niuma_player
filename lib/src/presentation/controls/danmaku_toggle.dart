import 'package:flutter/material.dart';

import 'package:niuma_player/src/niuma_sdk_assets.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_theme.dart';
import 'package:niuma_player/src/presentation/controls/niuma_sdk_icon.dart';

/// 弹幕开关——可视化 toggle，state 驱动外部 `ValueNotifier<bool>`。
///
/// 业务接弹幕系统时监听同一 ValueNotifier 决定是否渲染弹幕层。
class DanmakuToggle extends StatelessWidget {
  const DanmakuToggle({super.key, required this.visibility});

  final ValueNotifier<bool> visibility;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: visibility,
      builder: (ctx, on, _) {
        return InkWell(
          onTap: () => visibility.value = !on,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                NiumaSdkIcon(
                  asset: NiumaSdkAssets.danmakuToggleIcon(isOn: on),
                  color: theme.actionIconColor,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Container(
                  width: 22,
                  height: 12,
                  decoration: BoxDecoration(
                    color: on ? theme.primaryAccent : Colors.white24,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Align(
                    alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(1),
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
