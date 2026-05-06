import 'package:flutter/material.dart';

import 'package:niuma_player/src/niuma_sdk_assets.dart';
import 'package:niuma_player/src/presentation/core/niuma_player_theme.dart';
import 'package:niuma_player/src/presentation/controls/niuma_sdk_icon.dart';

/// 锁屏按钮——点击切 ic_lock ↔ ic_unlock 视觉。
///
/// 状态可外部传入（[locked]）让宿主跟其它 widget 同步监听 / freeze 控件；
/// 不传时本组件维护内部默认状态，仅做视觉演示。
///
/// 默认走 [NiumaPlayerTheme.actionIconColor]（白色，浮在视频上对比度高）；
/// 锁定时走 [NiumaPlayerTheme.primaryAccent] 提示当前是 active 状态。
class LockButton extends StatefulWidget {
  const LockButton({
    super.key,
    this.locked,
    this.onChanged,
  });

  /// 可选外部状态。null 时本组件持有内部默认状态。
  final ValueNotifier<bool>? locked;

  /// 状态变化回调。
  final ValueChanged<bool>? onChanged;

  @override
  State<LockButton> createState() => _LockButtonState();
}

class _LockButtonState extends State<LockButton> {
  late final ValueNotifier<bool> _internal;

  ValueNotifier<bool> get _src => widget.locked ?? _internal;

  @override
  void initState() {
    super.initState();
    _internal = ValueNotifier<bool>(false);
  }

  @override
  void dispose() {
    _internal.dispose();
    super.dispose();
  }

  void _toggle() {
    final next = !_src.value;
    _src.value = next;
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = NiumaPlayerTheme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: _src,
      builder: (ctx, locked, _) => IconButton(
        onPressed: _toggle,
        tooltip: locked ? '解锁' : '锁屏',
        // 锁屏 / 解锁两态都用同一个颜色（actionIconColor，默认白），
        // 不做 active 高亮——状态靠 lock ↔ unlock 图标本身区分。
        icon: NiumaSdkIcon(
          asset: locked ? NiumaSdkAssets.icLock : NiumaSdkAssets.icUnlock,
          color: theme.actionIconColor,
        ),
      ),
    );
  }
}
