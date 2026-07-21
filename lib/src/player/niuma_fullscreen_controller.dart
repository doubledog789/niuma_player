import 'package:flutter/foundation.dart'
    show
        ValueListenable,
        ValueNotifier,
        defaultTargetPlatform,
        kIsWeb,
        TargetPlatform;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart'
    show DeviceOrientation, SystemChrome, SystemUiMode;

/// 全屏的 headless 编排器：进 / 退全屏时的屏幕方向锁定 + system UI 切换。
/// 只管系统态；路由 push/pop 等 widget 部分由接入方全屏页负责。
/// Web 上 [SystemChrome] 是 no-op，[enter] / [exit] 只翻 [isFullscreen] 标志。
class NiumaFullscreenController {
  final ValueNotifier<bool> _isFullscreen = ValueNotifier<bool>(false);

  /// 全屏状态。
  ValueListenable<bool> get isFullscreen => _isFullscreen;

  /// 进全屏：竖直视频锁竖屏、否则锁横屏，system UI 切 immersiveSticky。
  /// [isVerticalVideo] 由调用方按 `controller.value.size` 判定。
  void enter({required bool isVerticalVideo}) {
    if (!kIsWeb) {
      SystemChrome.setPreferredOrientations(
        isVerticalVideo
            ? const <DeviceOrientation>[DeviceOrientation.portraitUp]
            : const <DeviceOrientation>[
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
      );
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _isFullscreen.value = true;
  }

  /// 退全屏：恢复方向锁 + system UI 回 edgeToEdge。
  /// Android 需两步：先锁 portraitUp 触发 surface 切回竖屏，下一帧再传空 list
  /// 释放（否则 Activity 停在横屏 config 直到物理旋转）；iOS/其它单步即可。
  void exit() {
    if (!kIsWeb) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        SystemChrome.setPreferredOrientations(
          const <DeviceOrientation>[DeviceOrientation.portraitUp],
        );
        SchedulerBinding.instance.addPostFrameCallback((_) {
          SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
        });
      } else {
        SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _isFullscreen.value = false;
  }

  /// 释放。
  void dispose() => _isFullscreen.dispose();
}
