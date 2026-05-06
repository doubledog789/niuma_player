import 'package:flutter/material.dart';

import 'package:niuma_player/src/niuma_sdk_assets.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_controller.dart';
import 'package:niuma_player/src/presentation/controls/icon_label_action.dart';
import 'package:niuma_player/src/presentation/controls/niuma_sdk_icon.dart';

/// mockup 风格的画中画按钮——icon + 「画中画」中文 label 垂直布局。
///
/// 实际进入 PiP 的回调由上层 NiumaPlayer 通过 [onTap] 注入。
class PipAction extends StatelessWidget {
  const PipAction({
    super.key,
    required this.controller,
    this.onTap,
  });

  final NiumaPlayerController controller;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconLabelAction(
      icon: const NiumaSdkIcon(asset: NiumaSdkAssets.icPip),
      label: '画中画',
      onTap: onTap ?? () {},
    );
  }
}
