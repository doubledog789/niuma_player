# niuma_player — 企业级 Dart 封装层设计

| | |
|---|---|
| 状态 | 设计稿 — 待评审 |
| 日期 | 2026-04-27 |
| 前置 | M3.x 内核完成（kernel 已就绪：状态机 + Try-Fail-Remember + 三端路由） |
| 范围 | Dart 层企业级封装（widget / 编排 / UX / 横切关注点） |
| 不含 | M4 缓存 / M5 预加载池 / DRM / 字幕（独立后续） |

---

## 0. 背景与设计原则

### 0.1 现状

M1–M3 已经交付**播放内核**（kernel）：
- `NiumaPlayerController` — 三端统一的 headless 控制器
- `NiumaPlayerView` — 裸 pixel widget
- 状态机 / 错误分级 / Try-Fail-Remember
- iOS / Android / Web 全链路打通

但这只是"能播"的最小集，离企业级 SDK 差着以下几件事：开箱即用 UI、业务编排、生命周期、UX 细节、可观测性。本 spec 设计这一层。

### 0.2 设计原则（贯穿所有章节）

1. **每一个 UX 行为都是参数，不是硬编码** — preset 决定默认值，不决定唯一行为。任何 tap / 倍速 / 锁屏 / 错误重试都可被业务方覆盖或禁用。
2. **kernel 行为不变** — 状态机 / Try-Fail-Remember / 三端路由不重做。允许向 `NiumaPlayerController` 增加可选构造参数（如 `middlewares`、多源 `NiumaMediaSource`）以承载新能力，但不改已有行为契约。
3. **headless 模式始终可用** — 业务方拿一个 `NiumaPlayerController` + `NiumaPlayerView` 自己拼 UI 永远工作。`NiumaVideoPlayer` 只是 Sensible Default 的成品组合。
4. **所有 orchestration 是纯 Dart**，可不依赖 platform 测试。
5. **YAGNI**：DRM / 字幕 / 多音轨 / DLNA 在本 spec 中**不做**，留给后续独立 milestone。

### 0.3 用户场景

- 长视频（剧集 / 教程）：tap 切控件、双击播放暂停、横滑 seek、纵滑亮度音量、长按倍速、上滑锁定、全屏锁屏、续播、多线路 + 多清晰度、VTT 预览图
- 短视频 reel：tap 直接播放暂停（无控件浮层）、双击点赞 hook、横滑禁用、纵滑亮度音量、长按倍速、上滑锁定、自动循环、列表化预加载（M5 范围）
- 通用：HTTP 防盗链 header、广告 cue（preRoll / midRoll / pauseAd / postRoll）、全埋点 hook、生命周期 / 路由暂停、错误重试

---

## 1. 架构分层

```
lib/
├── niuma_player.dart                 公共导出门面
├── testing.dart                      公开测试替身导出
└── src/
    ├── kernel/                       已有，不动
    │   ├── domain/
    │   ├── data/
    │   └── presentation/
    │
    ├── orchestration/                业务编排（纯 Dart，无 widget）
    │   ├── multi_source.dart
    │   ├── resume_position.dart
    │   ├── retry_policy.dart
    │   ├── ad_schedule.dart
    │   └── source_middleware.dart
    │
    ├── ux/                           UX 子系统
    │   ├── gestures/
    │   │   ├── gesture_arbiter.dart
    │   │   ├── long_press_speed.dart
    │   │   ├── seek_drag.dart
    │   │   ├── brightness_volume.dart
    │   │   └── gesture_bundle.dart
    │   ├── lifecycle/
    │   │   ├── lifecycle_policy.dart
    │   │   ├── app_state_observer.dart
    │   │   ├── route_observer.dart
    │   │   └── background_audio_coordinator.dart
    │   └── thumbnail/
    │       ├── vtt_loader.dart
    │       └── thumbnail_preview.dart
    │
    ├── ui/                           Widget 组装层（唯一引用 Material）
    │   ├── niuma_video_player.dart
    │   ├── controls/
    │   │   ├── slot_specs.dart
    │   │   ├── long_form_controls.dart
    │   │   └── short_form_controls.dart
    │   ├── overlays/
    │   │   ├── poster_overlay.dart
    │   │   ├── error_overlay.dart
    │   │   ├── loading_overlay.dart
    │   │   └── ad_overlay.dart
    │   └── theme/
    │       └── niuma_player_theme.dart
    │
    ├── observability/                横切：埋点
    │   ├── analytics_event.dart
    │   └── analytics_emitter.dart
    │
    └── testing/                      测试替身（公开）
        ├── fake_niuma_player_controller.dart
        ├── fake_resume_storage.dart
        ├── fake_analytics_emitter.dart
        ├── fake_network_observer.dart
        └── fake_route_observer.dart
```

层间依赖（自下而上）：

```
testing  ──→  kernel
ui       ──→  ux ──→ orchestration ──→ kernel
observability ←──── 被所有层调用
```

---

## 2. 公共 API：`NiumaVideoPlayer`

### 2.1 入口 widget

```dart
class NiumaVideoPlayer extends StatefulWidget {
  const NiumaVideoPlayer({
    required this.controller,
    this.controls = const NiumaLongFormControls(),
    this.gestures,                                 // null = 从 controls 推断
    this.lifecycle = const LifecyclePolicy.pauseOnLeave(),
    this.ads,
    this.poster,
    this.errorBuilder,
    this.loadingBuilder,
    this.resume,
    this.retryPolicy = const RetryPolicy.smart(),
    this.thumbnail,
    this.theme,
    this.analytics,
    this.aspectRatio,
    this.fullscreenRouteBuilder,
    this.multiSource = const MultiSourcePolicy.autoFailover(maxAttempts: 1),
    this.network,                                  // null = 网络切换检测 disabled
    this.backgroundAudio,                          // 必须配合 lifecycle.audioOnly()
    this.onLifecyclePrompt,                        // askUser 回调
    this.onResumePrompt,                           // resume.askUser 回调
  });
}
```

### 2.2 接入梯度

**5 行最简**：

```dart
final ctrl = NiumaPlayerController(NiumaDataSource.network(url));
await ctrl.initialize();
return NiumaVideoPlayer(controller: ctrl);
```

**短视频 reel**：

```dart
NiumaVideoPlayer(
  controller: ctrl,
  controls: NiumaShortFormControls(onLike: _handleLike),
)
```

**业务深度定制**：

```dart
NiumaVideoPlayer(
  controller: ctrl,
  controls: NiumaLongFormControls(
    topBar: MyCustomTopBar(),
    qualitySwitcher: MyQualitySwitcher(),
  ),
  ads: NiumaAdSchedule(
    preRoll: AdCue(builder: (_, ad) => MyBannerAd(adController: ad)),
    midRolls: [MidRollAd(at: 30.seconds, cue: ...)],
    pauseAd: AdCue(...),
    pauseAdShowPolicy: PauseAdShowPolicy.oncePerSession,
  ),
  resume: ResumePolicy(behaviour: ResumeBehaviour.askUser),
  analytics: (event) => myTracker.send(event),
  retryPolicy: RetryPolicy.exponential(maxAttempts: 3),
)
```

**Headless（业务方完全自画 UI）**：

```dart
return Stack([
  NiumaPlayerView(ctrl),           // 仅渲染像素
  MyCompletelyCustomControlsLayer(ctrl),
]);
```

Headless 模式下仍可独立 import 各 building block：`NiumaGestureBundle` / `LifecyclePolicy` / `ResumePolicy` / `AnalyticsEmitter` 都不绑死在 `NiumaVideoPlayer` 里。

### 2.3 控件 preset 的形状

```dart
@immutable
class NiumaLongFormControls extends NiumaControlsPreset {
  const NiumaLongFormControls({
    this.topBar,
    this.bottomBar,
    this.centerCluster,
    this.qualitySwitcher,
    this.speedSwitcher,
    this.lockButton,
    this.brightnessIndicator,
    this.volumeIndicator,
    this.seekIndicator,
  });
}
```

业务方可：
- 整个 preset 自己写一个 `class MyControls extends NiumaControlsPreset`
- 仅替换某槽：`NiumaLongFormControls(qualitySwitcher: MyWidget())`

形状 = 组合（value class with copyWith），不强制继承。

---

## 3. 手势仲裁器

### 3.1 抽象

```dart
enum GestureTrigger {
  tap, doubleTap,
  longPressDown, longPressUp,
  horizontalDrag, verticalDragLeft, verticalDragRight,
  upwardSwipeWhileLongPress,    // 长按中再上滑 → 锁倍速
  upwardSwipeWhileLocked,       // 锁定后再上滑 → 解锁
}

sealed class GestureAction {
  const GestureAction();
  static const disabled = _Disabled();
  const factory GestureAction.toggleControls()         = _ToggleControls;
  const factory GestureAction.togglePlayPause()        = _TogglePlayPause;
  const factory GestureAction.setSpeed(double speed)   = _SetSpeed;
  const factory GestureAction.lockSpeed(double speed)  = _LockSpeed;
  const factory GestureAction.unlockSpeed()            = _UnlockSpeed;
  const factory GestureAction.brightness()             = _Brightness;
  const factory GestureAction.volume()                 = _Volume;
  const factory GestureAction.seekDelta()              = _SeekDelta;
  const factory GestureAction.callback(VoidCallback f) = _Callback;
}

@immutable
class NiumaGestureBundle {
  const NiumaGestureBundle({...});
  const factory NiumaGestureBundle.longForm() = _LongFormBundle;
  const factory NiumaGestureBundle.shortForm() = _ShortFormBundle;
  NiumaGestureBundle copyWith({...});
}
```

### 3.2 状态机

```
idle
 ├─ down                                      → tracking
tracking
 ├─ up (≤ tapTimeout, 位移 < slop)            → fire(tap)            → idle
 ├─ up + 在 doubleTapInterval 内              → fire(doubleTap)       → idle
 ├─ longPressTimer (默认 500ms) fires         → fire(longPressDown)   → committed.longPress
 ├─ |Δx| > slop && |Δx|/|Δy| > 1.5            → committed.seek
 ├─ |Δy| > slop && |Δy|/|Δx| > 1.5, x 左半屏  → committed.brightness
 ├─ 同上, x 右半屏                            → committed.volume
committed.longPress
 ├─ up                                         → fire(longPressUp)     → idle
 ├─ Δy < -slop                                 → fire(upwardSwipeWhileLongPress)
                                                                      → committed.lockedSpeed
committed.lockedSpeed
 ├─ up                                         → idle (倍速锁定，banner 显示)
committed.seek / brightness / volume
 ├─ move                                       → fire 持续 delta
 ├─ up                                         → fire 终态                → idle

(独立)
idle (with _speedLocked == true) + 上滑          → fire(upwardSwipeWhileLocked)
                                              → 解锁
```

**不变量**：
- 一旦 commit 到任意轴，禁止跨轴切换
- 轴决议比值固定 1.5（不可配置）
- 长按 → 上滑锁定是同一指连续动作；解锁是独立的下一次 down

### 3.3 视觉反馈

```dart
sealed class GestureFeedback {
  const factory GestureFeedback.seek(Duration delta, Duration target);
  const factory GestureFeedback.brightness(double value);
  const factory GestureFeedback.volume(double value);
  const factory GestureFeedback.speedActive(double speed);
  const factory GestureFeedback.speedLocked(double speed);
  const factory GestureFeedback.idle();
}

abstract class GestureFeedbackBuilder {
  Widget build(BuildContext, GestureFeedback);
}
```

各 controls preset 自带默认 builder；业务方可整体替换。

### 3.4 状态归属

UI-only 瞬时状态归 `NiumaPresentationController`（内部 own，业务方零感知）：

```dart
class NiumaPresentationController extends ValueNotifier<NiumaPresentationValue> {
  // controlsVisible / speedLocked / fullscreen / lastGestureFeedback
}
```

`NiumaVideoPlayer.initState` 自己 new；不暴露外部传入。

### 3.5 实现要点

- `RawGestureDetector` + 自定义 `OneSequenceGestureRecognizer`
- 不能用 Flutter 默认 `GestureDetector`（无法做长按嵌套上滑）
- 在 GestureArenaTeam 中赢过滚动手势

---

## 4. 生命周期 & 焦点管理

### 4.1 触发点矩阵

| 触发点 | 默认 | 备选 |
|---|---|---|
| App 进后台 | `pause` | `keepPlaying` / `keepAudio` |
| App 回前台 | `resumeIfWasPlaying` | `stayPaused` |
| Route push | `pause` | `keepPlaying` |
| Route pop 回来 | `resumeIfWasPlaying` | `stayPaused` |
| Widget 卸载 | `dispose`（强制） | — |
| 系统抢音频焦点 | `pause` | — |
| 网络 wifi → cellular | `askUser` | `pause` / `keepPlaying` / `disabled` |

### 4.2 API

```dart
@immutable
class LifecyclePolicy {
  const LifecyclePolicy({
    this.onAppBackground          = LifecycleAction.pause,
    this.onAppForeground          = LifecycleAction.resumeIfWasPlaying,
    this.onRouteHidden            = LifecycleAction.pause,
    this.onRouteRevealed          = LifecycleAction.resumeIfWasPlaying,
    this.onAudioFocusLost         = LifecycleAction.pause,
    this.onAudioFocusGained       = LifecycleAction.resumeIfWasPlaying,
    this.onNetworkSwitchToCellular= LifecycleAction.askUser,
  });

  const factory LifecyclePolicy.pauseOnLeave();
  const factory LifecyclePolicy.keepPlayingInPip();
  const factory LifecyclePolicy.audioOnly();
}

sealed class LifecycleAction {
  static const pause                = _Pause();
  static const resumeIfWasPlaying   = _Resume();
  static const stayPaused           = _Stay();
  static const keepPlaying          = _Keep();
  static const askUser              = _AskUser();
  static const disabled             = _Disabled();
}
```

### 4.3 关键不变量

`resumeIfWasPlaying` 必须**只在自动暂停时记忆**才生效。手动暂停 → 进后台 → 回前台 → 仍保持暂停。`LifecycleArbiter._wasAutoPaused` 作为内部不可见标志。

### 4.4 路由可见性降级链

```
1. 优先：RouteAware (用户在 MaterialApp 注册 niumaPlayerRouteObserver)
2. 次选：VisibilityDetector (硬依赖 visibility_detector，自动 wrap)
3. 兜底：仅 AppLifecycle (推荐用户注册 RouteObserver)
```

`visibility_detector` 加进硬依赖（Google 官方维护，纯 Dart）。

### 4.5 网络切换

niuma_player **不直接依赖** `connectivity_plus`。业务方传 `Stream<NetworkType>`：

```dart
NiumaVideoPlayer(
  network: NetworkObserver.fromStream(myConnectivityStream),
)
```

不传 = 该触发点 disabled。文档示例展示如何用 `connectivity_plus` 接入。

### 4.6 askUser 回调

```dart
NiumaVideoPlayer(
  onLifecyclePrompt: (LifecyclePromptKind kind) async {
    return await showDialog<LifecycleAction>(...);
  },
)
```

`askUser` 但未传回调时静默降级到 `pause`。

### 4.7 背景音频持续（M6 — 独立子里程碑）

#### 跨端实现

```
LifecyclePolicy.audioOnly() 触发
        ↓
BackgroundAudioCoordinator
        ├── iOS
        │   ├── AVAudioSession.setCategory(.playback) + setActive(true)
        │   ├── MPNowPlayingInfoCenter (title/artist/artwork/position)
        │   └── MPRemoteCommandCenter (play/pause/skip/seek 绑定到 controller)
        ├── Android
        │   ├── ForegroundService 启动 (NiumaAudioService 由 plugin 提供)
        │   ├── MediaSessionCompat 注册
        │   ├── NotificationCompat.Builder + MediaStyle 渲染锁屏 / 通知栏
        │   └── ExoPlayerSession 切到 audio-only (停止视频解码)
        └── Web
            ├── navigator.mediaSession.setActionHandler + metadata
            └── 浏览器原生限制：tab 隐藏多数会暂停 <video>
```

#### 公共 API

```dart
@immutable
class BackgroundAudioConfig {
  const BackgroundAudioConfig({
    required this.title,
    this.artist,
    this.artworkUrl,
    this.allowSeek = true,
    this.allowSkipPrevious = false,
    this.allowSkipNext = false,
    this.onSkipPrevious,
    this.onSkipNext,
  });
}

NiumaVideoPlayer(
  lifecycle: const LifecyclePolicy.audioOnly(),
  backgroundAudio: BackgroundAudioConfig(...),
)
```

`audioOnly` 但 `backgroundAudio` 缺失：debug assert，release 降级到 `pause` + warning log。

#### 业务方接入清单

```
ios/Runner/Info.plist  →  UIBackgroundModes 加 "audio"
android/app/build.gradle  →  minSdk ≥ 21
android/app/src/main/AndroidManifest.xml  →
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
  <service android:name="cn.niuma.niuma_player.NiumaAudioService"
           android:foregroundServiceType="mediaPlayback"
           android:exported="false" />
```

#### 工作量估算

iOS 1d / Android 2–3d / Web 0.5d / Dart coordinator + 测试 1d = **5–6d**。M6 与 M7-M9 主线并行立项。

---

## 5. 广告 cue 系统

### 5.1 数据形状

```dart
@immutable
class NiumaAdSchedule {
  const NiumaAdSchedule({
    this.preRoll,
    this.midRolls = const <MidRollAd>[],
    this.pauseAd,
    this.postRoll,
    this.pauseAdShowPolicy = PauseAdShowPolicy.oncePerSession,
  });
}

@immutable
class MidRollAd {
  const MidRollAd({
    required this.at,
    required this.cue,
    this.skipPolicy = MidRollSkipPolicy.skipIfSeekedPast,
  });
}

enum MidRollSkipPolicy {
  fireOnce,
  fireEachPass,
  skipIfSeekedPast,    // ← default
}

enum PauseAdShowPolicy {
  always,
  oncePerSession,      // ← default
  cooldown,            // 配 cooldownDuration
}

@immutable
class AdCue {
  const AdCue({
    required this.builder,
    this.minDisplayDuration = const Duration(seconds: 5),
    this.timeout,
    this.dismissOnTap = false,
  });

  final Widget Function(BuildContext, AdController) builder;
}
```

### 5.2 AdController 契约

```dart
abstract class AdController {
  /// minDisplayDuration 之前调用：debug assert，release 静默忽略
  void dismiss();

  Duration get elapsed;
  Stream<Duration> get elapsedStream;

  void reportImpression();
  void reportClick();
}
```

业务方完全自画跳过按钮 / 倒计时 UI；niuma_player 不掺和。

### 5.3 调度逻辑

`AdSchedulerOrchestrator`（纯 Dart，可单测）：

```
监听 controller.value
  ├─ position 跨过 midRoll[i].at && 未 fired
  │     ├─ skipIfSeekedPast 且来源 = manual seek → 标 fired，不触发
  │     └─ else → fire(midRoll[i])
  ├─ phase: idle → ready + preRoll != null     → fire(preRoll)
  ├─ phase: playing → paused (manual) + pauseAd → 检查 pauseAdShowPolicy
  └─ phase: ended + postRoll != null            → fire(postRoll)

fire(cue):
  _activeCue.value = cue
  if controller.isPlaying: wasPlaying=true, pause()
  AdOverlay 监听 _activeCue → 渲染 cue.builder(ctx, AdControllerImpl)
  AdControllerImpl.dismiss() 调用：
    _activeCue.value = null
    if wasPlaying: play()
```

### 5.4 与生命周期的交互

- 广告活跃时进后台：`LifecyclePolicy` 仍处理（默认 pause），主视频本就停着，只是广告自身展示计时也暂停
- 路由 push：同上
- `LifecycleArbiter` 在恢复时检查 `AdSchedulerOrchestrator.adActive` —— 若 active，**不**自动 play 主视频，等 dismiss 后才恢复

### 5.5 Analytics 事件

```
ad_scheduled       (cueType, at?)
ad_impression      (cueType, durationShown)
ad_click           (cueType)
ad_dismissed       (cueType, reason: userSkip | timeout | dismissOnTap)
```

业务方注册 `AnalyticsEmitter` 一次，所有广告埋点自动触发。

---

## 6. 横切子系统

### 6.1 多源 / 多清晰度

```dart
@immutable
class NiumaMediaSource {
  factory NiumaMediaSource.single(NiumaDataSource source);
  factory NiumaMediaSource.lines({
    required List<MediaLine> lines,
    required String defaultLineId,
  });
}

@immutable
class MediaLine {
  const MediaLine({
    required this.id,
    required this.label,
    required this.source,
    this.quality,
    this.priority = 0,
  });
}

@immutable
class MediaQuality {
  const MediaQuality({this.heightPx, this.bitrate, this.codec});
}
```

切换流程：

```dart
await controller.switchLine('cdn-b-1080');
// 内部：保存 position → dispose 旧 backend → 新 backend with line.source
//      → seekTo(savedPosition) → if wasPlaying play()
```

新事件：

```dart
final class LineSwitching extends NiumaPlayerEvent { /* from, to */ }
final class LineSwitched  extends NiumaPlayerEvent { /* to */ }
final class LineSwitchFailed extends NiumaPlayerEvent { /* to, error */ }
```

#### 自动 failover

```dart
NiumaVideoPlayer(
  multiSource: const MultiSourcePolicy.autoFailover(maxAttempts: 1),  // ← default
  // 或 MultiSourcePolicy.manual()
)
```

触发条件：当前 line 抛 `network` 或 `terminal` 错。`codecUnsupported` 不切（换线路也解不开）。按 priority 顺序尝试。

**穷尽所有 line 仍失败**：保留最后一个 line 的错误状态（`phase=error`），让 `errorBuilder` / `ErrorOverlay` 接管 UI。不会循环重试——业务方决定下一步（手动重试 / 切换内容 / 关闭）。

### 6.2 续播

```dart
abstract class ResumeStorage {
  Future<Duration?> read(String key);
  Future<void> write(String key, Duration position);
  Future<void> clear(String key);
}

class _SharedPrefsResumeStorage implements ResumeStorage { ... }

@immutable
class ResumePolicy {
  const ResumePolicy({
    this.storage = const _SharedPrefsResumeStorage(),
    this.keyOf,
    this.behaviour = ResumeBehaviour.auto,
    this.minSavedPosition = const Duration(seconds: 30),
    this.discardIfNearEnd = const Duration(seconds: 30),
    this.savePeriod = const Duration(seconds: 5),
  });
}

enum ResumeBehaviour {
  auto,
  askUser,
  disabled,
}
```

`ResumeOrchestrator` 流程：
- `initialize()` 完成 → 读 `storage[keyOf(ds)]` → 按 behaviour 处理
- 每 5s 写一次 position（满足 minSavedPosition 后）
- `phase=ended` → `clear`
- `dispose` → 最后一次 write

### 6.3 VTT 进度条预览图

```dart
@immutable
class ThumbnailPreview {
  const ThumbnailPreview({
    required this.vttUrl,
    this.imageBaseUrl,
    this.cacheStrategy = ThumbnailCacheStrategy.memory,
    this.headers,
  });
}

class VttThumbnailLoader {
  Future<ImageProvider?> imageAt(Duration position);
  Rect? regionAt(Duration position);
}
```

`SeekIndicator` widget 在拖动 / hover 时调 loader.imageAt。

短视频 preset 内部忽略 `thumbnail` 参数（debug warning）。

### 6.4 Source middleware

```dart
abstract class SourceMiddleware {
  Future<NiumaDataSource> apply(NiumaDataSource input);
}
```

跑的时机：
- `initialize()` 之前
- `switchLine()` 之前（每条 line.source 都跑）
- `retryPolicy` 重试之前

典型实现：

```dart
class HeaderInjectionMiddleware extends SourceMiddleware {
  const HeaderInjectionMiddleware(this.headers);
  final Map<String, String> headers;

  @override
  Future<NiumaDataSource> apply(NiumaDataSource input) async {
    if (input.type != NiumaSourceType.network) return input;
    return NiumaDataSource.network(
      input.uri,
      headers: {...?input.headers, ...headers},
    );
  }
}

class SignedUrlMiddleware extends SourceMiddleware {
  SignedUrlMiddleware(this._signer);
  final Future<String> Function(String) _signer;

  @override
  Future<NiumaDataSource> apply(NiumaDataSource input) async {
    if (input.type != NiumaSourceType.network) return input;
    final signedUrl = await _signer(input.uri);
    return NiumaDataSource.network(signedUrl, headers: input.headers);
  }
}
```

注入：

```dart
NiumaPlayerController(
  initialSource,
  middlewares: [
    HeaderInjectionMiddleware({'Referer': 'https://app.example.com'}),
    SignedUrlMiddleware((url) => myBackend.signed(url)),
  ],
)
```

### 6.5 数据流总览

```
NiumaMediaSource.lines([...])
       ↓ pick defaultLine
   MediaLine.source (NiumaDataSource)
       ↓ middleware pipeline
   NiumaDataSource (final)
       ↓ kernel: NiumaPlayerController.initialize()
   ↑                                        ↓
ResumeOrchestrator                    NiumaPlayerValue
   (writes every 5s)                       ↓
   (reads on init,                  VttThumbnailLoader (lazy)
    seeks to savedPos)
```

---

## 7. 测试策略

### 7.1 分层测试矩阵

| 层 | 测试形态 | 优先级 |
|---|---|---|
| `kernel/` | 纯 Dart 单测 | P0（已完成） |
| `orchestration/` | 纯 Dart 单测 | **P0** |
| `ux/` | 纯 Dart 单测 + 必要 widget 测试 | P1 |
| `ui/` | Widget smoke + golden | P2 |
| `example/integration_test/` | 真机 E2E | P3（**不进 CI**，手动 / nightly） |

### 7.2 子系统 done 矩阵

| 子系统 | 单测 | Fake | Widget 测试 | 真机验证 |
|---|---|---|---|---|
| 多源 / 切线 | ✓ | ✓ | ✓ | ✓ |
| 续播 | ✓ | ✓ | ✓ | ✓ |
| Retry | ✓ | — | ✓ | ✓ |
| 广告 cue | ✓ | — | ✓ | ✓ |
| Source middleware | ✓ | — | — | ✓ |
| Gestures | ✓ | — | ✓ | ✓ (关键) |
| Lifecycle | ✓ | ✓ | ✓ | ✓ |
| Background Audio (M6) | ✓ | — | — | ✓ (锁屏 / 通知栏) |
| VTT 预览图 | ✓ | — | ✓ | ✓ |
| 全屏 / 锁屏 | — | — | ✓ | ✓ |
| 防盗链 header | ✓ | — | — | ✓ |

### 7.3 公开测试替身

`lib/testing.dart` 导出：

```dart
export 'src/testing/fake_niuma_player_controller.dart';
export 'src/testing/fake_resume_storage.dart';
export 'src/testing/fake_analytics_emitter.dart';
export 'src/testing/fake_network_observer.dart';
export 'src/testing/fake_route_observer.dart';
```

每个 fake：
- 实现公开抽象
- 暴露 `commandLog` / `eventLog` 列表
- 提供 `programmedResponses` 让测试编排响应

### 7.4 覆盖率（宽松阈值）

不设硬性 CI 阈值。开发阶段建议参考：
- orchestration ≥ 80%（业务逻辑）
- ux ≥ 70%（状态机）
- ui smoke 即可（不卡）

CI 运行 `flutter test --coverage` 上传 lcov.info 作 artifact，不 fail 阈值。

### 7.5 CI 调整

```yaml
jobs:
  unit-tests:           # 已有
    - flutter analyze
    - flutter test --coverage
    - upload coverage artifact

  golden:               # 新增，单独 job
    runs-on: ubuntu-latest
    - flutter test --tags golden

  build-{android,ios,web}: # 已有
    - 构建产物（已有）

  # integration_test 不进 CI
```

---

## 8. 实施里程碑分解

新增 4 个里程碑（M3 之后 / M4-M5 仍待定）：

```
M3.x ────► (DONE) kernel + 三端路由
                     │
                     ├──► M7  orchestration 层  (主线起点)
                     │      multi_source / resume / retry / ad_schedule / source_middleware
                     │      纯 Dart，无 widget，可独立测
                     │
                     ├──► M8  ux 层  (依赖 M7)
                     │      gesture_arbiter / lifecycle_policy + arbiter / vtt_loader
                     │      仍多数纯 Dart
                     │
                     ├──► M9  ui 层  (依赖 M7 + M8)
                     │      NiumaVideoPlayer / controls preset / overlays / theme
                     │
                     └──► M6  background audio (parallel，不 block 主线)
                            iOS AVAudioSession + MPRemoteCommandCenter
                            Android ForegroundService + MediaSession
                            Dart coordinator
```

工作量粗估：
- M7: 5d（含 `observability/` —— `AnalyticsEmitter` 是 orchestration 的依赖，不单独立项）
- M8: 4d
- M9: 6d
- M6: 5–6d（与 M7-M9 并行）

总计串行约 15d；M6 并行后挂钟时间约 15–17d。

每个里程碑内部包含**自身的测试**（kernel 之外的所有新代码都自带单测）。测试不单独立项。

---

## 9. 范围之外（明确不做）

本 spec 之外的功能：
- **M4 视频缓存层**（独立后续）
- **M5 短视频预加载池**（独立后续）
- **DRM**（Widevine / FairPlay）
- **字幕 / 多音轨**
- **DLNA / AirPlay 投屏**
- **画中画 PiP**（仅在 LifecyclePolicy.keepPlayingInPip 提到 — 实际 native 接线留给后续）
- **截图 / 录屏**
- **浮水印 / 防盗录**

这些都不在本设计中实现。preset / API 不为它们预留位置（YAGNI），需要时再开新 spec。

---

## 10. 待定问题

留给实施阶段的小决定（不阻塞设计批准）：

1. `NiumaPresentationController` 在 `NiumaVideoPlayer.dispose` 时是否一并 dispose？倾向是。
2. `MediaQuality.heightPx` 缺失（仅有 bitrate）的清晰度排序规则。倾向按 bitrate 升序回退。
3. `RetryPolicy.exponential` 默认参数（base / max delay）。倾向 base=1s, max=10s, attempts=3。
4. `analytics` 事件命名：snake_case 还是 camelCase？倾向 snake_case（贴合移动端埋点习惯）。
5. golden 测试是否引入 `golden_toolkit`？倾向是（多设备截图）。

---

## 11. 设计原则汇总（速查）

1. 行为可参数化，不锁死
2. kernel 不动，新功能向上叠
3. headless 模式始终可用
4. orchestration 全部可单测
5. preset = 默认值，不限制可扩展性
6. YAGNI

---

## 附录 A：导出表

`lib/niuma_player.dart` 公共导出：

```dart
// kernel (已有)
export 'src/kernel/...';

// orchestration
export 'src/orchestration/multi_source.dart';
export 'src/orchestration/resume_position.dart';
export 'src/orchestration/retry_policy.dart';
export 'src/orchestration/ad_schedule.dart';
export 'src/orchestration/source_middleware.dart';

// ux
export 'src/ux/gestures/gesture_bundle.dart' show NiumaGestureBundle, GestureAction, GestureTrigger, GestureFeedback;
export 'src/ux/lifecycle/lifecycle_policy.dart' show LifecyclePolicy, LifecycleAction, LifecyclePromptKind;
export 'src/ux/lifecycle/background_audio_coordinator.dart' show BackgroundAudioConfig;
export 'src/ux/lifecycle/route_observer.dart' show niumaPlayerRouteObserver;
export 'src/ux/thumbnail/thumbnail_preview.dart' show ThumbnailPreview, ThumbnailCacheStrategy;

// ui
export 'src/ui/niuma_video_player.dart';
export 'src/ui/controls/long_form_controls.dart';
export 'src/ui/controls/short_form_controls.dart';
export 'src/ui/controls/slot_specs.dart' show NiumaControlsPreset;
export 'src/ui/theme/niuma_player_theme.dart';

// observability
export 'src/observability/analytics_event.dart';
```

`lib/testing.dart` 测试替身：

```dart
export 'src/testing/fake_niuma_player_controller.dart';
export 'src/testing/fake_resume_storage.dart';
export 'src/testing/fake_analytics_emitter.dart';
export 'src/testing/fake_network_observer.dart';
export 'src/testing/fake_route_observer.dart';
```

---

## 附录 B：依赖变更

`pubspec.yaml` 新增：

```yaml
dependencies:
  visibility_detector: ^0.4.0+2  # 路由可见性兜底
  shared_preferences: ^2.2.0     # ResumeStorage 默认实现
  # connectivity_plus 不加 — 由业务方决定
```

`example/pubspec.yaml` 新增（用于 demo）：

```yaml
dependencies:
  connectivity_plus: ^6.0.0   # 演示如何接入 network 切换
```

`dev_dependencies`：

```yaml
golden_toolkit: ^0.15.0       # golden 测试
```
