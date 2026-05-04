import 'package:flutter/material.dart';

import '../../niuma_sdk_assets.dart';
import '../niuma_danmaku_controller.dart';
import '../niuma_danmaku_scope.dart';
import 'niuma_sdk_icon.dart';

/// 弹幕开关按钮。
///
/// 三档可达性：
/// 1. 显式 [danmakuController] → 用它
/// 2. 否则 [NiumaDanmakuScope.maybeOf] → 用注入的 controller
/// 3. 都没有 → [IgnorePointer]，灰色禁用图标
///
/// 点击切换 [DanmakuSettings.visible]。设置面板（字号/透明度/区域）请用
/// 独立的 [DanmakuSettingsPanel]——本按钮**不**承载二级菜单。
class DanmakuButton extends StatelessWidget {
  /// 构造一个按钮。
  const DanmakuButton({super.key, this.danmakuController});

  /// 显式 controller；不传则走 scope 兜底。
  final NiumaDanmakuController? danmakuController;

  @override
  Widget build(BuildContext context) {
    final ctl = danmakuController ?? NiumaDanmakuScope.maybeOf(context);
    if (ctl == null) {
      return const IgnorePointer(
        ignoring: true,
        child: IconButton(
          onPressed: null,
          icon: NiumaSdkIcon(
            asset: NiumaSdkAssets.icDanmakuOff,
            color: Colors.white38,
          ),
          tooltip: '弹幕（未注入 controller）',
        ),
      );
    }
    return AnimatedBuilder(
      animation: ctl,
      builder: (ctx, _) {
        final on = ctl.settings.visible;
        return IconButton(
          onPressed: () => ctl.updateSettings(
              ctl.settings.copyWith(visible: !on)),
          icon: NiumaSdkIcon(
            asset: NiumaSdkAssets.danmakuToggleIcon(isOn: on),
            color: Colors.white,
          ),
          tooltip: on ? '关闭弹幕' : '开启弹幕',
        );
      },
    );
  }
}
