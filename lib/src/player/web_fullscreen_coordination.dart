import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/widgets.dart';

/// Web 全屏路由计数——有 N 个全屏页处于活跃路由栈时为 N。
///
/// inline [NiumaPlayerView]（不在 [NiumaFullscreenScope] 子树里那一份）监听
/// 本计数：>0 时返 ColoredBox 不挂 HtmlElementView，让 wrapper `<video>`
/// 元素留在 fullscreen 那侧的 platform-view 容器里。
///
/// **必须用进程级计数而不是 backend 自家 ValueNotifier**：line failover 触发
/// backend swap 时新 backend 默认 `_isWebFullscreen=false`——inline 误判成
/// "已退出全屏"重新挂 HtmlElementView 抢回 wrapper，fullscreen 那边落空黑屏
/// （音频还在因为 video 元素本身没坏，只是被错误地搬到 inline 容器了）。
/// 进程级计数跟全屏页路由生命周期挂钩，与 backend 实例解耦——backend 怎么换
/// 都不影响当前是否处于全屏。
///
/// io 平台不需要本计数（Texture / Surface 可以多处复用同一 textureId），
/// 但为简化代码 [NiumaPlayerView] 在所有平台都读这个值——非 web 平台
/// 永远 0，分支不命中。
///
/// **职责划分（headless 核 ↔ 参考皮）**：这是 core ↔ 参考皮之间的 **web 全屏
/// 协调原语**。核里的 [NiumaPlayerView] *读* [webFullscreenRouteCountListenable]
/// 和 [NiumaFullscreenScope] marker；参考皮里的全屏页 widget 负责在进退全屏时调
/// [enterWebFullscreenRoute] / [exitWebFullscreenRoute] *增减* 计数、并在子树外
/// 包一层 [NiumaFullscreenScope]。两者通过本文件这套小契约解耦。
///
/// 这里刻意 **不** 暴露裸 [ValueNotifier]：只读侧给
/// [webFullscreenRouteCountListenable]，写侧给一对语义明确的 enter / exit
/// 协调 API，避免参考皮直接 `.value = ...` 把计数写坏。
final ValueNotifier<int> _webFullscreenRouteCount = ValueNotifier<int>(0);

/// 公开只读视图——给 [NiumaPlayerView] 等下游 listener 用，不允许外部修改。
ValueListenable<int> get webFullscreenRouteCountListenable =>
    _webFullscreenRouteCount;

/// 进入一个 web 全屏路由：计数 +1。参考皮的全屏页在 push 时调一次。
void enterWebFullscreenRoute() {
  _webFullscreenRouteCount.value = _webFullscreenRouteCount.value + 1;
}

/// 退出一个 web 全屏路由：计数 -1（下限 0）。参考皮的全屏页在 pop 时调一次。
void exitWebFullscreenRoute() {
  if (_webFullscreenRouteCount.value > 0) {
    _webFullscreenRouteCount.value = _webFullscreenRouteCount.value - 1;
  }
}

/// 全屏页用来标记"此 subtree 处于全屏路由内"的 [InheritedWidget] marker。
///
/// 核里的 [NiumaPlayerView] 用 [maybeOf] 判断自己是 inline 那份还是
/// 全屏那份，决定把 `HtmlElementView` 挂哪边（web 单 `<video>` 不能两处
/// mount）。参考皮的全屏页负责在内嵌播放器外包一层 [NiumaFullscreenScope]。
class NiumaFullscreenScope extends InheritedWidget {
  /// 构造一个 marker scope。
  const NiumaFullscreenScope({super.key, required super.child});

  /// 找最近的 [NiumaFullscreenScope]——存在即返回非空 marker。
  static NiumaFullscreenScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NiumaFullscreenScope>();
  }

  @override
  bool updateShouldNotify(NiumaFullscreenScope oldWidget) => false;
}
