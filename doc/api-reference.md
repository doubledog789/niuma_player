# API Reference

`niuma_player`（headless 播放内核）公开符号速查。所有内容通过单一 barrel
`package:niuma_player/niuma_player.dart` 暴露——`import` 它即可访问全部。

> 本包零 UI widget（除无样式渲染面 `NiumaPlayerView`）。控件由你监听
> `controller.value` 自己拼。复杂控件参考实现在 git 历史的 niuma_ui 参考皮里。

---

## 目录

- [NiumaPlayerController](#niumaplayercontroller)
- [NiumaPlayerView](#niumaplayerview)
- [NiumaDataSource / NiumaMediaSource](#niumadatasource--niumamediasource)
- [NiumaPlayerOptions](#niumaplayeroptions)
- [NiumaPlayerValue / PlayerPhase](#niumaplayervalue--playerphase)
- [NiumaPlayerEvent](#niumaplayerevent)
- [手势 / 全屏 headless controller](#手势--全屏-headless-controller)
- [投屏（Cast）](#投屏cast)
- [工具函数](#工具函数)

---

## NiumaPlayerController

`extends ValueNotifier<NiumaPlayerValue>`——一切从这里开始，监听它拼 UI。

```dart
NiumaPlayerController(
  this.source, {                              // NiumaMediaSource
  this.middlewares = const [],                // List<SourceMiddleware>
  this.retryPolicy = const RetryPolicy.smart(),
  NiumaPlayerOptions? options,
  PlatformBridge? platform,                   // 测试 inject
  BackendFactory? backendFactory,             // 测试 inject
})

// 单 source 便捷 factory：
NiumaPlayerController.dataSource(NiumaDataSource ds, {NiumaPlayerOptions? options});
```

**生命周期 / 播放控制**：
```dart
await controller.initialize();              // 异步初始化 backend
controller.play();
controller.pause();
controller.seekTo(Duration);
controller.setPlaybackSpeed(double);
controller.setVolume(double);
await controller.dispose();
```

**多线路**：
```dart
await controller.switchLine('lineId');      // 主动切线路
controller.activeLineId;                     // 当前线路 id（getter）
```

**PiP**：
```dart
await controller.enterPictureInPicture();   // 须 user gesture 触发，返回 bool
await controller.exitPictureInPicture();
controller.autoEnterPictureInPictureOnBackground = true;  // 切后台自动进 PiP
```

**值流 / 事件流**：
```dart
controller.value;                            // 当前 NiumaPlayerValue
controller.addListener(() {...});            // 值变化（ValueNotifier）
controller.events.listen((e) {...});         // Stream<NiumaPlayerEvent>
```

**Android Try-Fail-Remember 清缓存**：
```dart
await NiumaPlayerController.clearDeviceMemory();   // 静态方法
```

---

## NiumaPlayerView

无样式渲染面——一块视频纹理（iOS / Android）/ `<video>` 表面（Web）。自己用
`AspectRatio` / `FittedBox` 包它控制尺寸。

```dart
AspectRatio(
  aspectRatio: 16 / 9,
  child: NiumaPlayerView(controller),
)
```

视频自然分辨率从 `controller.value.size` 拿，可据此动态算 aspectRatio。

---

## NiumaDataSource / NiumaMediaSource

`NiumaDataSource`——单个流地址：
```dart
NiumaDataSource.network('https://...', headers: {...});
NiumaDataSource.asset('assets/video.mp4');
NiumaDataSource.file('/path/to/video.mp4');
```

`NiumaMediaSource`——单线路或多线路：
```dart
// 单线路：
NiumaMediaSource.single(NiumaDataSource.network('https://...'));

// 多线路：
NiumaMediaSource.lines(
  lines: [
    MediaLine(
      id: 'cdn1',
      label: '线路一',
      priority: 0,            // 越小越早尝试（auto-failover）
      source: NiumaDataSource.network('https://...'),
      quality: null,         // 可选 MediaQuality 元数据
    ),
    MediaLine(id: 'cdn2', label: '线路二', priority: 1, source: ...),
  ],
  defaultLineId: 'cdn1',
);
```

---

## NiumaPlayerOptions

行为 policy——**默认值就是推荐值**，特殊场景再覆盖。

| 字段 | 默认 | 说明 |
|---|---|---|
| `initTimeout` | `30s` | 单次 initialize wall-clock 上限 |
| `forceIjkOnAndroid` | `false` | Android 跳过 ExoPlayer 直走 IJK（debug / A/B） |
| `rollbackOnSwitchFailure` | `true` | 用户主动切换失败 → 静默回滚原线路 |
| `autoFailoverOnInitialError` | `true` | 默认线路 init 失败 → 按 priority 升序遍历下一条 |
| `unsafePipAutoBackgroundOnEnter` | `false` | iOS PiP 后调私有 API 切后台。**⚠️ App Store 不兼容** |

```dart
const NiumaPlayerOptions(
  rollbackOnSwitchFailure: true,
  autoFailoverOnInitialError: true,
  forceIjkOnAndroid: false,
)
```

---

## NiumaPlayerValue / PlayerPhase

`controller.value` 的类型——监听它驱动全部 UI。

```dart
class NiumaPlayerValue {
  final PlayerPhase phase;
  final Duration position;                    // 当前位置
  final Duration duration;                    // 总时长
  final Duration bufferedPosition;            // 已缓冲位置
  final Size size;                            // 视频自然分辨率
  final double playbackSpeed;
  final PlayerError? error;                   // phase==error 时非 null
  final bool isInPictureInPicture;
  final bool isPictureInPictureSupported;

  bool get initialized;                       // 已 init 且不在 opening
  bool get isPlaying;                         // phase == playing
  bool get hasError;                          // phase == error
}
```

```dart
enum PlayerPhase {
  idle,            // 未 init
  opening,         // initialize() 进行中
  ready,           // 已 init，未播
  playing,
  paused,
  buffering,
  ended,
  error,           // 看 value.error
}
```

```dart
class PlayerError {
  final PlayerErrorCategory category;   // network / codecUnsupported / terminal / transient / unknown
  final String message;
  final String? code;
}
```

---

## NiumaPlayerEvent

`controller.events` 的元素类型。都是 `final class`，用 `is` 判断。

| 事件 | 触发时机 |
|---|---|
| `BackendSelected(kind, fromMemory)` | initialize 选定 backend（iOS/Android/Web） |
| `FallbackTriggered(reason, errorCode)` | Android ExoPlayer → IJK 兜底 |
| `LineSwitching(fromId, toId)` | 主动切换线路开始 |
| `LineSwitched(toId)` | 切换成功 |
| `LineSwitchFailed(toId, error)` | 切换失败（即使 rollback 成功也 emit，供业务上报） |
| `PipModeChanged(isInPip)` | 进入 / 退出 PiP（原生侧推送） |
| `PipRemoteAction(action)` | PiP 小窗按钮事件 |
| `CastStarted(session)` | 投屏开始 |
| `CastEnded(reason)` | 投屏结束（`CastEndReason`） |

---

## 手势 / 全屏 headless controller

核只提供**编排逻辑**，HUD / 全屏 UI 由你自己摆。

### NiumaGestureController

把拖动几何量映射成播放意图 + HUD 反馈状态：
```dart
final gesture = NiumaGestureController(controller: controller, /* ... */);
gesture.feedback;   // ValueListenable<GestureFeedbackState?>，监听它渲染你的 HUD
```

手势值对象：
```dart
enum GestureKind {
  horizontalSeek,    // 水平拖快进/退
  brightness,        // 左半屏垂直拖亮度（仅 native）
  volume,            // 右半屏垂直拖音量（仅 native）
  longPressSpeed,    // 长按倍速
  doubleTap,         // 双击 toggle play/pause
}
```

`GestureFeedbackState` 只产出语义 `GestureHudIcon`（不带 `IconData`）——你在 HUD
里把它映射到自家图标资源。

### NiumaFullscreenController

进 / 退全屏的屏幕方向锁定 + system UI 切换 headless 编排（按视频比例锁方向，
web 上 no-op）：
```dart
final fs = NiumaFullscreenController(/* ... */);
```

### Web 全屏路由协调

单 `<video>` 在 inline / 全屏路由间搬迁的契约——`NiumaPlayerView` 读它：
```dart
NiumaFullscreenScope                       // marker widget，包住全屏路由
enterWebFullscreenRoute();
exitWebFullscreenRoute();
webFullscreenRouteCountListenable;         // ValueListenable<int>，只读
```

---

## 投屏（Cast）

核只保留**值类型 + 协调入口**。协议实现（DLNA / AirPlay）与投屏 UI 在 git 历史
的参考皮里——你实现 `CastService` 产出 `CastSession` 交给核。

```dart
await controller.connectCast(CastSession session);
await controller.disconnectCast(reason: CastEndReason.userCancelled);
controller.castSession;                     // ValueListenable<CastSession?>

controller.events.listen((e) {
  if (e is CastStarted) { /* e.device: CastDevice */ }
  if (e is CastEnded)   { /* e.reason: CastEndReason */ }
});
```

值类型：
```dart
class CastDevice { /* id / name / ... */ }
abstract class CastSession {
  CastDevice get device;
  ValueListenable<CastConnectionState> get state;
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<Duration> getPosition();      // disconnect 时本地 seek 接续用
  Future<void> disconnect();
}
enum CastConnectionState { idle, discovering, connecting, connected, error }
enum CastEndReason { userCancelled, networkError, deviceLost, timeout }
```

---

## 工具函数

```dart
formatVideoTime(Duration);   // → 'mm:ss' / 'h:mm:ss'，进度 / 时间 label 用
NiumaSdkAssets.hlsJsUrl;     // web 后端 hls.js 资源路径常量
```

---

## 进一步阅读

- [`doc/getting-started.md`](getting-started.md) — 接入步骤
- [`example/lib/main.dart`](../example/lib/main.dart) — 最小 demo 源码
- [`CHANGELOG.md`](../CHANGELOG.md) — 版本变更记录
- [`README.md`](../README.md) — 项目主页
