import 'package:flutter/material.dart';
import '../../cast/cast_session.dart';
import '../niuma_player_controller.dart';

/// 投屏中视频区中央覆盖层。castSession=null 时不渲染。
///
/// 显示元素：设备 icon + "投屏中" 字 + 设备名。半透明黑底盖在视频上，
/// 让用户清楚当前正在远程投屏。
class NiumaCastOverlay extends StatelessWidget {
  const NiumaCastOverlay({super.key, required this.controller});

  /// 被监听的 controller。
  final NiumaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CastSession?>(
      valueListenable: controller.castSession,
      builder: (ctx, session, _) {
        if (session == null) return const SizedBox.shrink();
        return Container(
          color: Colors.black54,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(session.device.icon,
                  size: 48, color: Colors.lightBlueAccent),
              const SizedBox(height: 12),
              const Text(
                '投屏中',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                session.device.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
