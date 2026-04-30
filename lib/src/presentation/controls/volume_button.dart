import 'package:flutter/material.dart';

import '../niuma_player_controller.dart';
import '../niuma_player_theme.dart';

/// 静音 / 取消静音切换按钮。
///
/// 内部维护一个简单 mute 状态，点击切换并调 [NiumaPlayerController.setVolume]
/// `0.0` / `1.0`。M9 阶段不暴露音量滑条；M10+ 再加长按 slider。
class VolumeButton extends StatefulWidget {
  /// 创建一个 [VolumeButton]。
  const VolumeButton({super.key, required this.controller});

  /// 该按钮控制其音量的 player controller。
  final NiumaPlayerController controller;

  @override
  State<VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<VolumeButton> {
  bool _muted = false;

  void _toggle() {
    setState(() {
      _muted = !_muted;
    });
    widget.controller.setVolume(_muted ? 0.0 : 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return IconButton(
      padding: EdgeInsets.zero,
      iconSize: theme.iconSize,
      color: theme.iconColor,
      icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
      onPressed: _toggle,
    );
  }
}
