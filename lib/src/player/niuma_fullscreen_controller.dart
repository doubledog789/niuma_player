import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart'
    show DeviceOrientation, SystemChrome, SystemUiMode;

/// 全屏的 **headless 编排器**——封装"进 / 退全屏时的屏幕方向锁定 + system UI
/// 模式切换"这段纯系统态逻辑，从全屏页 widget 里剥出来，可独立测试。
///
/// **边界**：本类只管系统态（朝向 / SystemUI / [isFullscreen] 标志）。路由
/// push/pop、`HtmlElementView` 重挂、Web 根背景刷黑、续播兜底等 **widget 相关**
/// 的部分仍由参考皮里的全屏页 widget 持有——它在 io 平台 initState/dispose 时
/// 调本类的 [enter] / [exit]，web 平台自己处理 DOM 搬迁。
///
/// Web 上 [SystemChrome] 是 no-op，[enter] / [exit] 只翻 [isFullscreen] 标志，
/// 朝向/沉浸由浏览器与页面 widget 负责。
class NiumaFullscreenController {
  /// 当前是否处于全屏。参考皮的全屏页可监听它切换渲染。
  final ValueNotifier<bool> _isFullscreen = ValueNotifier<bool>(false);

  /// 全屏状态。
  ValueListenable<bool> get isFullscreen => _isFullscreen;

  /// 进全屏：按视频自然比例锁方向（竖直视频锁竖屏，否则锁横屏左右），
  /// system UI 切 immersiveSticky。[isVerticalVideo] 由调用方按
  /// `controller.value.size` 判定（height > width）。
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
  ///
  /// Android 两步走：先显式 [DeviceOrientation.portraitUp] 给 Activity 一个
  /// "竖屏"信号触发 onConfigurationChanged 把 surface 切回竖屏，下一帧再传
  /// 空 list 释放锁定（否则 Activity 停在横屏 config 直到物理旋转）。iOS/其它
  /// 单步传空 list 即可（host Info.plist 若只声明 landscape，portrait 请求会
  /// 撞 UISceneError 噪音）。
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
