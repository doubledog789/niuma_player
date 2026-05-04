import 'package:flutter/material.dart';

import '../../niuma_sdk_assets.dart';
import '../niuma_player_controller.dart';
import 'icon_label_action.dart';
import 'niuma_sdk_icon.dart';

/// mockup 风格的投屏按钮——icon + 「投屏」中文 label 垂直布局。
///
/// 实际打开 cast picker 的回调由上层 NiumaPlayer 通过 [onTap] 注入；
/// 本 widget 不直接调 NiumaCastService。
class CastAction extends StatelessWidget {
  const CastAction({
    super.key,
    required this.controller,
    this.onTap,
  });

  final NiumaPlayerController controller;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconLabelAction(
      icon: const NiumaSdkIcon(asset: NiumaSdkAssets.icCast),
      label: '投屏',
      onTap: onTap ?? () {},
    );
  }
}
