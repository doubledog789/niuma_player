import 'package:flutter/material.dart';
import '../../cast/cast_session.dart';
import '../niuma_player_controller.dart';
import 'niuma_cast_picker.dart';

/// 投屏按钮。inline / 投屏中两态自动切。
///
/// `castSession.value == null` 时显示 outlined cast 图标，tap 弹完整
/// picker 扫描设备。`castSession.value != null` 时显示高亮 cast_connected
/// 图标 + 设备名 chip，tap 弹简化 picker（切换 / 断开）。
class NiumaCastButton extends StatelessWidget {
  const NiumaCastButton({super.key, required this.controller});

  /// 被驱动的 controller。
  final NiumaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CastSession?>(
      valueListenable: controller.castSession,
      builder: (ctx, session, _) {
        if (session == null) {
          return IconButton(
            icon: const Icon(Icons.cast, color: Colors.white),
            onPressed: () => NiumaCastPicker.show(ctx, controller),
            tooltip: '投屏',
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(
                Icons.cast_connected,
                color: Colors.lightBlueAccent,
              ),
              onPressed: () =>
                  NiumaCastPicker.showConnected(ctx, controller, session),
              tooltip: '投屏中',
            ),
            Flexible(
              child: Text(
                session.device.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.lightBlueAccent,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        );
      },
    );
  }
}
