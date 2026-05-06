import 'package:flutter/material.dart';
import 'package:niuma_player/src/cast/cast_session.dart';
import 'package:niuma_player/src/niuma_sdk_assets.dart';
import 'package:niuma_player/src/presentation/controls/niuma_sdk_icon.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_controller.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_theme.dart';

/// 投屏按钮。inline / 投屏中两态自动切。
///
/// `castSession.value == null` 时显示 outlined cast 图标，tap 触发 [onTap]。
/// `castSession.value != null` 时显示高亮 cast_connected 图标 + 设备名 chip，
/// tap 同样触发 [onTap]（由调用方决定弹 picker 还是 panel）。
///
/// [onTap] 由宿主（如 [NiumaPlayer]）注入，默认 null（按钮显示但无操作）。
class NiumaCastButton extends StatelessWidget {
  const NiumaCastButton({
    super.key,
    required this.controller,
    this.onTap,
  });

  /// 被驱动的 controller。
  final NiumaPlayerController controller;

  /// tap 回调——调用方负责决定展示哪种 cast picker。
  /// 为 null 时按钮不响应点击。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return ValueListenableBuilder<CastSession?>(
      valueListenable: controller.castSession,
      builder: (ctx, session, _) {
        if (session == null) {
          return IconButton(
            icon: NiumaSdkIcon(
              asset: NiumaSdkAssets.icCast,
              color: theme.iconColor,
            ),
            onPressed: onTap,
            tooltip: '投屏',
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const NiumaSdkIcon(
                asset: NiumaSdkAssets.icCastConnected,
                color: Colors.lightBlueAccent,
              ),
              onPressed: onTap,
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
