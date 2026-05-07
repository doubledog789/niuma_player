import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:niuma_player/src/presentation/core/niuma_player_controller.dart';

/// `NiumaPlayerView` 通过 maybeOf 检测当前 build context 是否在 web
/// fullscreen overlay 子树内——决定是渲染 video 还是 SizedBox。
///
/// **机制**：web fullscreen 时单 `<video>` element 不能在两个 widget tree
/// 位置同时 mount。用 InheritedWidget 标记 fullscreen overlay 那侧，inline
/// 那侧（marker 不在）则渲染 SizedBox 让 element 让给 overlay。
class WebFullscreenOverlayMarker extends InheritedWidget {
  const WebFullscreenOverlayMarker({super.key, required super.child});

  static bool isInside(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WebFullscreenOverlayMarker>() != null;
  }

  /// 不订阅版本——build 期间 check 用，避免不必要 rebuild。
  static bool isInsideStatic(BuildContext context) {
    return context.getInheritedWidgetOfExactType<WebFullscreenOverlayMarker>() != null;
  }

  @override
  bool updateShouldNotify(WebFullscreenOverlayMarker oldWidget) => false;
}

/// 当前 active 的 web fullscreen OverlayEntry——单进程级最多 1 个。
OverlayEntry? _activeFullscreenEntry;

/// 进入 web "Flutter Overlay 假全屏"：
/// 1. 通知 backend 翻 webFullscreenState=true
/// 2. 在 Navigator overlay 上 insert 一个全屏 OverlayEntry，含黑色背景
///    + 用同一 controller 的 NiumaPlayer + 业务传入的 fullscreen widget
///    builder
///
/// 调 [enterWebFlutterFullscreen] 时业务传 fullscreenChildBuilder——通常
/// 是 NiumaFullscreenButton 自己拼装一个 NiumaPlayer 复用同 controller。
/// 进入 / 退出由 [exitWebFlutterFullscreen] 配对调用。
///
/// io 平台 (kIsWeb=false) no-op。
Future<void> enterWebFlutterFullscreen({
  required BuildContext context,
  required NiumaPlayerController controller,
  required Widget Function(BuildContext) fullscreenChildBuilder,
}) async {
  if (!kIsWeb) return;
  if (_activeFullscreenEntry != null) return; // already in fullscreen
  // 在 await 前抓 Overlay 引用——避免 use_build_context_synchronously
  final overlay = Overlay.of(context, rootOverlay: true);
  await controller.enterNativeFullscreen(); // 通知 backend
  final entry = OverlayEntry(
    builder: (ctx) => Material(
      color: Colors.black,
      child: WebFullscreenOverlayMarker(
        child: fullscreenChildBuilder(ctx),
      ),
    ),
  );
  _activeFullscreenEntry = entry;
  overlay.insert(entry);
}

Future<void> exitWebFlutterFullscreen({
  required NiumaPlayerController controller,
}) async {
  if (!kIsWeb) return;
  await controller.exitNativeFullscreen();
  _activeFullscreenEntry?.remove();
  _activeFullscreenEntry = null;
}

bool isWebFlutterFullscreenActive() => kIsWeb && _activeFullscreenEntry != null;
