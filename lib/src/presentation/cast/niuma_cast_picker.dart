import 'package:flutter/material.dart';
import '../../cast/cast_session.dart';
import '../niuma_player_controller.dart';

/// 投屏设备选择 / 投屏中切换断开 bottom sheet。
/// Task 9 会实装；目前只是 CastButton 引用的 placeholder。
class NiumaCastPicker {
  NiumaCastPicker._();

  static void show(BuildContext ctx, NiumaPlayerController controller) {
    // Task 9 实装
  }

  static void showConnected(
    BuildContext ctx,
    NiumaPlayerController controller,
    CastSession session,
  ) {
    // Task 9 实装
  }
}
