# API Reference

`niuma_player` 公开符号速查。所有内容通过单一 barrel `package:niuma_player/niuma_player.dart` 暴露——业务方只需 `import 'package:niuma_player/niuma_player.dart';` 即可访问全部。

---

## 目录

- [核心类](#核心类)
  - [NiumaPlayerController](#niumaplayercontroller)
  - [NiumaMediaSource](#niumamediasource)
  - [NiumaPlayerOptions](#niumaplayeroptions)
- [UI 组件](#ui-组件)
  - [NiumaPlayer](#niumaplayer)
  - [NiumaShortVideoPlayer](#niumashortvideoplayer)
  - [NiumaFullscreenPage](#niumafullscreenpage)
  - [反馈 UI](#反馈-ui)
- [控件层](#控件层)
  - [NiumaControlButton enum](#niumacontrolbutton)
  - [NiumaControlBarConfig](#niumacontrolbarconfig)
  - [ButtonOverride](#buttonoverride)
- [事件与状态](#事件与状态)
  - [NiumaPlayerValue](#niumaplayervalue)
  - [PlayerPhase](#playerphase)
  - [NiumaPlayerEvent](#niumaplayerevent)
- [手势](#手势)
- [弹幕](#弹幕)
- [投屏](#投屏)

---

## 核心类

### NiumaPlayerController

播放器主控制器——一切都从这里开始。

```dart
NiumaPlayerController(
  this.source, {                              // NiumaMediaSource
  this.middlewares = const [],                // 数据源 middleware 流水线
  this.retryPolicy = const RetryPolicy.smart(),
  NiumaPlayerOptions? options,
  PlatformBridge? platform,                   // 测试 inject
  BackendFactory? backendFactory,             // 测试 inject
  ThumbnailFetcher? thumbnailFetcher,
})

// 单 URL 便捷 factory：
NiumaPlayerController.dataSource(NiumaDataSource ds, {NiumaPlayerOptions? options, ...})
```

**生命周期**：
```dart
await controller.initialize();    // 异步初始化 backend
controller.play();
controller.pause();
controller.seekTo(Duration);
controller.setSpeed(double);
controller.setVolume(double);
await controller.dispose();
```

**多线路**：
```dart
await controller.switchLine('lineId');                    // 主动切线路
controller.activeLineId;                                  // 当前线路 id (getter)
```

**PiP**：
```dart
await controller.enterPictureInPicture();                 // 必须 user gesture trigger
await controller.exitPictureInPicture();
controller.autoEnterPictureInPictureOnBackground = true;  // app 切后台自动进 PiP
```

**投屏**：
```dart
await controller.connectCast(CastSession session);
await controller.disconnectCast({playLocalAfter: true});
controller.castSession;                                    // ValueListenable<CastSession?>
```

**事件流 + 值流**：
```dart
controller.events.listen((NiumaPlayerEvent e) {...});      // 事件
controller.addListener(() {...});                          // 值变化（ValueNotifier）
controller.value;                                          // 当前 NiumaPlayerValue
```

**清缓存**（Android Try-Fail-Remember）：
```dart
await NiumaPlayerController.clearDeviceMemory();           // 静态方法
```

---

### NiumaMediaSource

数据源——单线路或多线路。

```dart
// 单线路：
NiumaMediaSource.single(
  NiumaDataSource.network('https://...'),
  thumbnailVtt: 'https://.../thumbnails.vtt',  // 可选 M8 缩略图
);

// 多线路：
NiumaMediaSource.lines(
  lines: [
    MediaLine(
      id: 'cdn1',
      label: '线路一',
      priority: 0,                              // 越小越早尝试（auto-failover）
      source: NiumaDataSource.network('https://...'),
    ),
    MediaLine(id: 'cdn2', label: '线路二', priority: 1, source: ...),
  ],
  defaultLineId: 'cdn1',
  thumbnailVtt: 'https://.../thumbnails.vtt',   // 可选
);

// 访问：
source.lines;             // List<MediaLine>
source.lineById(id);      // MediaLine?
source.currentLine;       // MediaLine（默认线路）
source.defaultLineId;     // String
```

`NiumaDataSource`：
```dart
NiumaDataSource.network('https://...', headers: {...});
NiumaDataSource.asset('assets/video.mp4');
NiumaDataSource.file('/path/to/video.mp4');
```

---

### NiumaPlayerOptions

行为 policy 配置——**默认值就是 SDK 推荐**，特殊场景再覆盖。

| 字段 | 默认 | 说明 |
|---|---|---|
| `initTimeout` | `30s` | 单次 initialize wall-clock 上限 |
| `forceIjkOnAndroid` | `false` | Android 跳过 ExoPlayer 直走 IJK（debug / A/B 测试） |
| `rollbackOnSwitchFailure` | `true` | 用户主动切换失败 → 静默回滚原线路（**v0.9.1+**） |
| `autoFailoverOnInitialError` | `true` | 默认线路 init 失败 → 按 priority 升序遍历下一条（**v0.9.1+**） |
| `unsafePipAutoBackgroundOnEnter` | `false` | iOS PiP 后调私有 API 切后台。**⚠️ 非 App Store 兼容** |
| `thumbnailFetchTimeout` | `30s` | 默认 VTT 拉取 wall-clock 上限 |
| `thumbnailMaxBodyBytes` | `5 MiB` | VTT body 大小硬上限 |

```dart
const NiumaPlayerOptions(
  rollbackOnSwitchFailure: true,
  autoFailoverOnInitialError: true,
  forceIjkOnAndroid: false,
)
```

---

## UI 组件

### NiumaPlayer

长视频外壳——bili 风全屏 + inline 默认行为。

```dart
NiumaPlayer({
  required NiumaPlayerController controller,

  // ─── 主题 ───
  NiumaPlayerTheme? theme,                   // null = NiumaPlayerThemeData inherited

  // ─── 广告 ───
  NiumaAdSchedule? adSchedule,
  AnalyticsEmitter? adAnalyticsEmitter,
  bool pauseVideoDuringAd = true,

  // ─── 控件条配置 ───
  NiumaControlBarConfig? controlBarConfig,                    // inline 控件
  NiumaControlBarConfig fullscreenControlBarConfig = bili,    // 全屏控件
  Map<NiumaControlButton, ButtonOverride>? buttonOverrides,

  // ─── 业务 slot ───
  WidgetBuilder? actionsBuilder,                // 顶栏 enum 之后追加
  WidgetBuilder? bottomActionsBuilder,          // 底栏右组首位（v0.9.1+ 移到右组）
  WidgetBuilder? bottomTrailingBuilder,         // 底栏右组次位
  WidgetBuilder? rightRailBuilder,              // 全屏右侧互动栏
  WidgetBuilder? pausedOverlayBuilder,          // 暂停态业务 overlay
  List<PopupMenuEntry<dynamic>> Function(BuildContext)? moreMenuBuilder,

  // ─── 反馈 UI（v0.8+）───
  WidgetBuilder? loadingBuilder,
  Widget Function(BuildContext, PlayerError)? errorBuilder,
  WidgetBuilder? endedBuilder,
  VoidCallback? onErrorRetry,                   // 默认 NiumaErrorView 的 callback
  VoidCallback? onEndedReplay,                  // 默认 NiumaEndedView 的 callback

  // ─── 手势 ───
  Set<GestureKind> disabledGestures = const {},
  GestureHudBuilder? gestureHudBuilder,
  bool gesturesEnabledInline = false,

  // ─── 弹幕 ───
  NiumaDanmakuController? danmakuController,
  VoidCallback? onDanmakuInputTap,

  // ─── M16 元数据 ───
  String? title,
  String? subtitle,
  List<Duration>? chapters,                     // 进度条 chapter marks

  // ─── 自动行为 ───
  Duration controlsAutoHideAfter = const Duration(seconds: 5),
})
```

---

### NiumaShortVideoPlayer

短视频抖音风外壳——竖屏 PageView 翻页流。

```dart
NiumaShortVideoPlayer({
  required NiumaPlayerController controller,
  bool isActive = true,                                // PageView 协调
  bool loop = true,
  bool muted = false,
  BoxFit fit = BoxFit.cover,
  Widget Function(BuildContext, NiumaPlayerValue)? overlayBuilder,
  void Function(NiumaPlayerController)? onSingleTap,   // null = toggle play/pause
  NiumaShortVideoTheme? theme,
  NiumaDanmakuController? danmakuController,
  Widget Function(BuildContext, NiumaPlayerController)? leftCenterBuilder,
})
```

业务接入典型用法：
```dart
PageView.builder(
  itemBuilder: (ctx, i) => NiumaShortVideoPlayer(
    controller: controllers[i],
    isActive: i == currentIndex,
    overlayBuilder: (ctx, value) => MyLikeShareColumn(),
    leftCenterBuilder: (c, ctl) =>
        NiumaShortVideoFullscreenButton(controller: ctl),
  ),
)
```

---

### NiumaFullscreenPage

全屏 route——`FullscreenButton` / `NiumaShortVideoFullscreenButton` push 后跳到这里。

```dart
Navigator.of(context).push(
  NiumaFullscreenPage.route(
    controller: controller,
    fullscreenControlBarConfig: NiumaControlBarConfig.bili,
    title: '剧名',
    subtitle: '第 12 集',
    chapters: [Duration(seconds: 30), ...],
    // ... 其它参数同 NiumaPlayer
  ),
);
```

行为（v0.9.1+）：
- **iOS / Android**：按视频比例自动锁方向（`controller.value.size.height > .width` → 锁 portrait；否则 landscape）
- **Web**：无法 lock 方向，竖屏 viewport + 横屏视频时浮"旋转屏幕"提示 5s
- 视频 fit 智能选择：默认 `BoxFit.contain` letterbox；web fullscreen + 竖直视频 → `BoxFit.cover` 填满

---

### 反馈 UI

SDK 内置 3 个默认反馈 widget。业务方通过 `NiumaPlayer.loadingBuilder/errorBuilder/endedBuilder` 替换；不传走默认。

| Widget | phase | 默认行为 |
|---|---|---|
| `NiumaLoadingIndicator` | `opening` / `buffering` | 牛马橙圆形 spinner + "正在加载…" 文案 |
| `NiumaErrorView` | `error` | 错误图标 + `PlayerError.message` + 可选"重试"按钮（`onErrorRetry`） |
| `NiumaEndedView` | `ended` | 重播按钮（`onEndedReplay`） |

`NiumaProgressThumb`：进度条拖动时的 thumb 头像，支持 `iconBuilder` slot 替换 niuma 表情。

---

## 控件层

### NiumaControlButton

控件 enum——配置 / override / 自定义控件条都用这个。

```dart
enum NiumaControlButton {
  back,            // 返回按钮（顶栏左）
  title,           // 标题文本（顶栏左）
  cast,            // 投屏按钮
  pip,             // 画中画按钮
  lineSwitch,      // 线路切换 pill（多线路时显示）
  more,            // ⋮ 三点菜单
  playPause,       // 播放暂停
  speed,           // 速度选择 "1.0x"
  danmakuToggle,   // 弹幕开关 icon + switch
  danmakuInput,    // 弹幕输入 pill "发个友善的弹幕见证当下"
  subtitle,        // 字幕按钮（自家实现）
  volume,          // 静音 toggle
  fullscreen,      // 全屏按钮
  timeDisplay,     // 时间显示
  scrubBar,        // 进度条
}
```

每个 enum 对应 SDK 内置 widget，详见 `NiumaControlButtonResolver`。

---

### NiumaControlBarConfig

声明式配置——选哪些 button、放哪一侧、按什么顺序。

```dart
const NiumaControlBarConfig(
  topLeading: [NiumaControlButton.back, NiumaControlButton.title],
  topActions: [NiumaControlButton.more],
  bottomLeft: [
    NiumaControlButton.playPause,
    NiumaControlButton.danmakuToggle,
    NiumaControlButton.danmakuInput,
  ],
  bottomRight: [NiumaControlButton.speed, NiumaControlButton.lineSwitch],
  centerPlayPause: true,        // 中央大圆 PlayPause
  showProgressBar: true,        // 时间 + ScrubBar 区域
)
```

3 个内置 preset：
- `NiumaControlBarConfig.minimal`：最简（playPause + fullscreen）
- `NiumaControlBarConfig.bili`：bili mockup 风（默认 fullscreen 用这个）
- `NiumaControlBarConfig.full`：全开（含 cast / pip / lineSwitch / volume / subtitle / 弹幕）

---

### ButtonOverride

按钮级 override——把 enum 槽换成自家 widget。

```dart
buttonOverrides: {
  // 完全自定义（任意 widget）：
  NiumaControlButton.speed: ButtonOverride.builder((ctx) => MyCustomSpeedSheet()),

  // 沿用 SDK IconLabelAction 但换 icon / label / onTap：
  NiumaControlButton.cast: ButtonOverride.fields(
    icon: Icon(Icons.tv),
    label: '投到电视',
    onTap: () => showMyCastSheet(),
  ),
}
```

---

## 事件与状态

### NiumaPlayerValue

`controller.value` 的类型——subscribe 它通过 `ValueListenableBuilder` 或 `addListener`。

```dart
class NiumaPlayerValue {
  final PlayerPhase phase;                    // playing / paused / buffering / ...
  final Duration position;                    // 当前播放位置
  final Duration duration;                    // 视频总时长
  final Duration bufferedPosition;            // 已 buffer 位置
  final Size size;                            // 视频自然分辨率（width × height）
  final double playbackSpeed;
  final PlayerError? error;                   // phase=error 时非 null
  final bool isInPictureInPicture;
  final bool isPictureInPictureSupported;     // 设备是否支持 PiP

  bool get initialized;                       // 等价 phase != idle && phase != opening
  bool get isPlaying;                         // 等价 phase == playing
}
```

### PlayerPhase

```dart
enum PlayerPhase {
  idle,            // 未 init
  opening,         // initialize() 进行中
  ready,           // 已 init，未播
  playing,         // 播放中
  paused,          // 暂停
  buffering,       // 缓冲中
  ended,           // 播完
  error,           // 错误（看 value.error）
}
```

### NiumaPlayerEvent

`controller.events` 的元素类型。所有事件都是 `final class`，可用 `is` 判断。

| 事件 | 触发时机 |
|---|---|
| `BackendSelected(kind, fromMemory)` | initialize 选定 backend（iOS/Android/Web） |
| `FallbackTriggered(reason, errorCode)` | Android ExoPlayer → IJK 兜底 |
| `LineSwitching(fromId, toId)` | 主动切换线路开始 |
| `LineSwitched(toId)` | 切换成功 |
| `LineSwitchFailed(toId, error)` | 切换失败（即使 rollback 成功也会 emit 用于业务上报） |
| `PipModeChanged(isInPip)` | 进入 / 退出 PiP（原生侧推送） |
| `PipRemoteAction(action)` | PiP 小窗按钮事件（如 `playPauseToggle`） |
| `CastStarted(session)` | 投屏开始 |
| `CastEnded(reason)` | 投屏结束（用户 / 网络断 / 错误） |

`PlayerError`：
```dart
class PlayerError {
  final PlayerErrorCategory category;   // network / codecUnsupported / terminal / transient / unknown
  final String message;
  final String? code;
}
```

---

## 手势

### GestureKind

```dart
enum GestureKind {
  horizontalSeek,    // 水平拖快进/退
  brightness,        // 左半屏垂直拖亮度（仅 native）
  volume,            // 右半屏垂直拖音量（仅 native）
  longPressSpeed,    // 长按 2x 倍速
  doubleTap,         // 双击 toggle play/pause
}
```

### NiumaGestureLayer

业务一般不直接用——`NiumaPlayer` 内部已挂。如要嵌别处：

```dart
NiumaGestureLayer(
  controller: controller,
  enabled: true,
  disabledGestures: { GestureKind.brightness },
  hudBuilder: (ctx, state) => MyCustomHud(state),
  onTap: () => toggle控件可见(),
  child: NiumaPlayerView(controller),
)
```

### NiumaGestureHud（默认 HUD）

抖音风（v0.9.1+）：
- `horizontalSeek`：方向箭头 + brand 橙 delta tag (`+10s`) + 30pt target time + dim 总时长 + brand 橙细进度条
- `brightness`：暖金图标 + 百分比 + 暖金进度条
- `volume`：白图标 + 百分比 + brand 橙进度条
- `longPressSpeed`：圆角胶囊 "2x 倍速"
- `doubleTap`：圆形图标闪现

业务想自定义视觉：传 `gestureHudBuilder: (ctx, state) => MyHud(state)`。

---

## 弹幕

### NiumaDanmakuController

```dart
final danmaku = NiumaDanmakuController()
  ..addAll([
    DanmakuItem(position: Duration(seconds: 5), text: 'awsl', color: Colors.white),
    // ...
  ]);

// 单条添加：
danmaku.add(DanmakuItem(position: ..., text: ..., color: ..., fontSize: 18));

// 设置：
danmaku.updateSettings(DanmakuSettings(
  visible: true,
  fontScale: 1.2,
  opacity: 0.9,
  displayAreaPercent: 0.5,    // 弹幕占视频 50% 高度
  scrollDuration: Duration(seconds: 8),
));

// 重置（视频换源时调）：
danmaku.resetForNewSource();

// dispose 时：
danmaku.dispose();
```

### DanmakuItem

```dart
DanmakuItem(
  position: Duration(seconds: 30),    // 弹幕在视频的哪个位置
  text: '前方高能',
  color: Colors.white,                 // 默认白
  fontSize: 18,                        // 基础字号（受 settings.fontScale 缩放）
  mode: DanmakuMode.rolling,           // rolling / topPin / bottomPin
  pool: null,                          // 池标签（业务自管，SDK 不读）
  metadata: null,                      // 业务自管 metadata
)
```

### DanmakuSettingsPanel

SDK 自带的设置 UI——字号 / 透明度 / 显示区域 % 三档。业务想自定义不用这个。

```dart
showModalBottomSheet(
  context: ctx,
  builder: (sctx) => DanmakuSettingsPanel(danmaku: danmakuController),
);
```

---

## 投屏

### NiumaCastRegistry

进程级单例——SDK v0.9 起首次访问 `all()` / `byProtocolId()` 时**自动 register** `DlnaCastService` + `AirPlayCastService`，业务零配置。

业务自家协议（如 Chromecast）显式注册：
```dart
void main() {
  NiumaCastRegistry.register(MyChromecastService());
  runApp(...);
}
```

### CastService / CastSession

抽象层——业务一般不直接用。`NiumaCastButton` / `NiumaCastPickerPanel` 是消费者。

```dart
abstract class CastService {
  String get protocolId;              // 'dlna' / 'airplay' / 'chromecast'
  String get displayName;
  Stream<List<CastDevice>> discover();
  Future<CastSession> connect(CastDevice, NiumaPlayerController);
}

abstract class CastSession {
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration);
  Future<void> setVolume(double);
  Future<void> disconnect();
  ValueListenable<CastConnectionState> get connectionState;
  // ...
}
```

---

## 进一步阅读

- [`docs/getting-started.md`](getting-started.md) — 5 分钟接入
- [`example/`](../example/) — 8 个完整 demo 源码
- [`CHANGELOG.md`](../CHANGELOG.md) — 版本变更记录
- [`README.md`](../README.md) — 项目主页
