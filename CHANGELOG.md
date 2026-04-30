# Changelog

本项目所有显著变更都会记录在本文件中。

格式遵循 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/spec/v2.0.0.html)。

## [Unreleased]

### 新增（M9 review 修复）
- `AdDismissReason` 枚举新增 `error` 值——`NiumaAdOverlay` 在
  `cue.builder` 抛异常时使用 `AdDismissed(reason: error)` 而不是
  冒充 `timeout`，避免污染分析仪表盘的 timeout 指标。Non-breaking
  enum 扩展。
- `AdControllerImpl` 新增 `dispose()`：关闭内部 broadcast
  `StreamController`（`_elapsedCtrl`）。`NiumaAdOverlay` 在 cue 非
  userSkip 路径下也正确释放 controller，修复了 timeout / dismissOnTap
  / dismissActive 路径下的 StreamController 泄漏。
- 内部 `InheritedWidget` marker `NiumaPlayerConfigScope`（不导出，仅内部
  使用）—— `NiumaPlayer` 在 build 顶上注入外层配置，`FullscreenButton`
  在 push 全屏 route 时通过它把 `adSchedule` / `adAnalyticsEmitter` /
  `pauseVideoDuringAd` / `controlsAutoHideAfter` / `theme` 一起带进
  全屏页。
- 内部 `InheritedWidget` marker `NiumaFullscreenScope`（不导出，仅内部
  使用）——`FullscreenButton` 用 `maybeOf(context) != null` 准确检测
  "当前是否在全屏页内"，而不再用脆弱的 `!route.isFirst` 兜底（原方案
  在 example demo 等任意非 home 路由上都会误判成 pop）。
- `NiumaFullscreenPage.route()` 工厂签名增加 `adSchedule` /
  `adAnalyticsEmitter` / `pauseVideoDuringAd` / `controlsAutoHideAfter`
  / `theme` 参数，全部透传到全屏页内部的 `NiumaPlayer`，修复全屏页丢失
  外层配置。
- `NiumaPlayer` 加 `didUpdateWidget`：controller swap 时 detach 旧
  listener + 重建 orchestrator + attach 新 controller；`adSchedule`
  swap 时只重建 orchestrator——之前用户 swap controller 后内部
  状态停在 stale 实例。`NiumaAdOverlay` 同理。

### 变更（M9 review 修复）
- `AdSchedulerOrchestrator._fire` 强制先 `activeCue.value = null`
  再 set 新 cue，避免连续 fire 同一 cue 实例时 `ValueNotifier`
  short-circuit 不通知 listener。
- `NiumaPlayer._onTapVideo` 在 ad cue 活跃时直接 return 不切换
  controls 可见——把 tap 让给 `NiumaAdOverlay` 自己的 dismissOnTap
  接管，避免双层 gesture 冲突。
- `NiumaPlayer._setControlsVisible` 用 `_pendingVisibleIntent` 字段
  存最新意图——多次入队的 post-frame callback 读字段拿"最后一次写入"，
  避免旧 intent 覆盖新 intent。
- `NiumaPlayerTheme.accentColor` dartdoc 明确生效范围："仅作用于
  `ScrubBar` active 段 + thumb，不作用于普通图标按钮（图标按钮统一
  用 `iconColor`）"。

### 移除（M9 review 修复）
- `NiumaPlayer.showThumbnailPreview` 占位字段——M9 阶段 `ScrubBar`
  自己根据 `controller.source.thumbnailVtt` 决定是否启用预览，本字段
  从未生效，删之。

### 修复（M9 round-2 review）
- `FullscreenButton` 在 push 全屏 route 时，`NiumaPlayerConfigScope.theme`
  为 `null` 时 fallback 到 `NiumaPlayerTheme.of(context)`——这样 README
  推荐写法 `NiumaPlayerThemeData(child: NiumaPlayer(...))` 注入的主题
  也能透传到全屏页，不再回退到默认主题（视觉回归）。
- `NiumaAdOverlay.didUpdateWidget` orchestrator swap 分支：旧
  orchestrator 还持有 active cue 且 cue 进入前视频在播时，先恢复
  `videoController.play()` 再做 detach / reset——之前会让视频留在
  paused 状态。
- `NiumaPlayer.didUpdateWidget` 加 `controlsAutoHideAfter` 字段 diff：
  改了 props 立即 cancel 旧 timer，按当前 phase 用新值重新 schedule。
  之前老 timer 仍按旧值跑。
- `NiumaPlayer._onTapVideo` 改用 `_setControlsVisible` 走统一入口（不
  再直接 `setState`），让"build 阶段保护"逻辑天然覆盖到 tap 路径。
- `NiumaAdOverlay._onActiveCueChanged` 切换分支不再递归 self：抽出
  `_handleNewCue(cue)` 直接调，避免 `_lastCue` 来回写两遍。

### 移除导出（M9 round-2 review）
- `NiumaPlayerConfigScope` 与 `NiumaFullscreenScope` 从公开 API 中移除
  导出（`lib/niuma_player.dart`），它们是纯内部 `InheritedWidget`
  marker：前者用于 `FullscreenButton` push 全屏 route 时透传外层配置，
  后者用于让 `FullscreenButton` 检测"当前是否处于全屏页内"。用户从不
  需要直接构造它们；单测如需验证行为通过 `package:niuma_player/src/...`
  的内部路径 import。

## [0.4.0] - 2026-04-30

### 新增（M9 — UI overlay 层）
- `NiumaPlayer` 一体化默认播放组件——5 行起步：传一个
  `NiumaPlayerController` 即可拿到完整可用的播放界面（B 站风格底栏 +
  auto-hide + 进度条缩略图预览 + 可选广告 overlay + 全屏入口）。
- `NiumaFullscreenPage` + `NiumaFullscreenPage.route(controller)` 路由
  工厂——push 进全屏页（淡入 200ms），自动锁定 landscape +
  `SystemUiMode.immersiveSticky`；dispose 恢复 `DeviceOrientation.values`
  + `edgeToEdge`。Web 上 `kIsWeb` 保护跳过 SystemChrome 调用。
- `NiumaPlayerTheme` `InheritedWidget`（13 字段）+ `NiumaPlayerThemeData`，
  支持 host app 注入自定义 accent / 图标尺寸 / 进度条尺寸 / 缩略图
  预览尺寸 / 控件背景渐变等。
- 9 个原子控件：`PlayPauseButton` / `ScrubBar` / `TimeDisplay` /
  `VolumeButton` / `SpeedSelector`（0.5×–2×）/ `QualitySelector`
  （消费 `source.lines` + `switchLine`）/ `SubtitleButton`（M9 disabled，
  M10 启用）/ `DanmakuButton`（M9 disabled，M11 启用）/ `FullscreenButton`。
  全部对外 export，调用方可自己拼非默认布局。
- `NiumaControlBar` —— B 站风格密集底栏，把 9 个原子控件 + ScrubBar 按
  "上 ScrubBar / 下 Row" 两层组合；背景走主题 `controlsBackgroundGradient`。
- `NiumaScrubPreview` —— 进度条 hover / 拖动时悬浮缩略图组件，消费 M8
  `controller.thumbnailFor` + `NiumaThumbnailView`，可选时间标签。
- `NiumaAdOverlay` —— 把 `AdSchedulerOrchestrator.activeCue` 翻译成屏上
  widget；自动暂停 / 恢复底层视频、跑 `cue.timeout` 倒计时、捕获
  `cue.builder` 异常时 emit `AdDismissed` 并清场。
- `NiumaPlayer.adSchedule` 非空时在内部自动构造
  `AdSchedulerOrchestrator` + `NiumaAdOverlay`；`adAnalyticsEmitter`
  路由 `AdImpression` / `AdClick` / `AdDismissed` 事件。
- Auto-hide 状态机：进入 `playing` 5s（默认，可配 `controlsAutoHideAfter`）
  自动隐藏控件；`paused` 强制显示；点击视频区翻转显隐；广告 cue
  active 时强制隐藏让 overlay 接管；`Duration.zero` 视为永不自动隐藏。

### 变更（M7 follow-up）
- `AdSchedulerOrchestrator` 新增 `activeCueType: ValueNotifier<AdCueType?>`
  与 `dismissActive()`，让 overlay 在构造 `AdControllerImpl` 时知道
  cue 类型，用来给 `AdImpression` / `AdClick` / `AdDismissed` 标记
  正确的 `AdCueType`。
- `AdControllerImpl` 真实落实 `reportImpression`（去重，仅发一次）/
  `reportClick` / `dismiss` 路由——`dismiss` 在 `cue.minDisplayDuration`
  内静默拒绝，超过后 emit `AdDismissed(userSkip)` + 调
  `onDismissRequested` 让 overlay 收回。

## [0.3.0] - 2026-04-30

### 新增（M8 — 缩略图 VTT）
- `NiumaMediaSource.thumbnailVtt` 可选字段，传入 WebVTT thumbnail track URL。
- `controller.thumbnailFor(Duration position) → ThumbnailFrame?` —— 按播放位置查
  对应缩略图（sprite 图引用 + 裁剪矩形）。复杂度 O(log n)（二分查找）。
- `controller.thumbnailLoadState` getter + `ThumbnailLoadState`
  enum（`none / idle / loading / ready / failed`），让 UI 区分加载阶段。
- `NiumaThumbnailView` 助手 widget —— 一行渲染 `ThumbnailFrame`（封装
  `ImageStream` 同步触发防御 + sprite crop），上层不再需要重写 30 行
  ImageStream listener boilerplate。
- 内置 `WebVttParser.parseThumbnails`：支持 MM:SS.mmm / HH:MM:SS.mmm 时间格式
  和 `sprite.jpg#xywh=x,y,w,h` 引用语法；单条 cue 解析失败会跳过不影响整体。
- `ThumbnailCache`：sprite URL 去重 + LRU 淘汰（默认 32 张上限，覆盖长视频
  典型 sprite 数）。
- 公共类型导出：`ThumbnailFrame`、`WebVttCue`、`ThumbnailLoadState`、
  `NiumaThumbnailView`（其他实现细节内部化）。
- VTT URL 走 `SourceMiddleware` 流水线（跟视频 URL 同样的签名 / header 规则）。
- VTT 加载失败静默降级：不抛异常，只 log 一条，`thumbnailFor` 返回 null，
  视频播放完全不受影响。
- `controller.dispose()` 时清空 controller-local 引用并 `evict` 全局
  `PaintingBinding.imageCache` 中已解码的位图，sprite 像素不会长期占住 RAM。
- 新增依赖 `package:http ^1.0.0`，跨平台 VTT fetch（VM 走 `dart:io`，web 自动
  走 `XMLHttpRequest`；CORS 由调用方保证）。

## [0.2.0] - 2026-04-29

### 新增（M7 — 编排层）
- `NiumaMediaSource`（`single` + `lines` 两个 factory），承载带 `MediaQuality` 的 `MediaLine` 列表。
- `MultiSourcePolicy.autoFailover(maxAttempts: 1)`（默认）/ `MultiSourcePolicy.manual()`。
- `NiumaPlayerController.switchLine(id)` + `LineSwitching` / `LineSwitched` /
  `LineSwitchFailed` 事件；切换时保留位置和播放状态。
- `AutoFailoverOrchestrator` —— 仅在 `network` / `terminal` 错误时挑选下一条优先级
  线路（codec-unsupported 直接短路）；priority 升序（数值小的先尝试）。
  **注意**：M7 把它作为独立 helper 交付，controller 还没消费它。把
  `MultiSourcePolicy` 接入 controller 留到后续里程碑。
- `SourceMiddleware` 抽象类 + `HeaderInjectionMiddleware` + `SignedUrlMiddleware`
  + `runSourceMiddlewares` 流水线；在 backend init、switchLine、retry 之前都跑一次
  —— 每次都拿到新鲜的 headers / 重新签名的 URL。
- `NiumaPlayerController` 构造函数新增可选 `middlewares` 参数；流水线在
  backend 启动之前执行。
- `ResumeStorage`（抽象类）+ `SharedPreferencesResumeStorage`（默认实现）+
  `ResumePolicy` + `ResumeBehaviour`（`auto` / `askUser` / `disabled`）+
  `ResumeOrchestrator`（init 时读、周期性保存、ended 清空、dispose 时终态写入）。
- `RetryPolicy.smart()` / `.exponential()` / `.none()`。`NiumaPlayerController`
  在 `backend.initialize()` 周围应用该策略（默认 `smart` 对 `network` + `transient`
  类错误最多重试 3 次，指数退避 1s → 10s）；原有的 forceIjk Try-Fail-Remember
  兜底层在下面继续工作。
- `AdCue` + `AdController` 协议 + `NiumaAdSchedule` + `MidRollAd` +
  `MidRollSkipPolicy` + `PauseAdShowPolicy`。
- `AdSchedulerOrchestrator` 覆盖 preRoll（idle→ready）、midRoll（默认
  `skipIfSeekedPast`）、pauseAd（默认 `oncePerSession` + 可选 `cooldown`）、
  postRoll（phase=ended）。注意：`AdControllerImpl` 在内部存在用于强制
  `minDisplayDuration` 才允许 dismiss，但**不是** M7 公开 API ——
  orchestrator 目前只更新 `activeCue`，把它和 `cue.builder` 串起来的
  controller 接入留到 M9。
- `AnalyticsEvent` sealed 体系（`AdScheduled` / `AdImpression` / `AdClick` /
  `AdDismissed`）+ `AnalyticsEmitter` typedef hook。
- 公开测试 double 通过 `package:niuma_player/testing.dart` 提供：
  `FakeResumeStorage`、`FakeAnalyticsEmitter`。

### 变更
- `NiumaPlayerController` 首参数类型：`NiumaDataSource` → `NiumaMediaSource`。
  单源场景用 `NiumaPlayerController.dataSource(ds)` factory（旧调用点 drop-in
  替换）。`dataSource` getter 仍然返回 `source.currentLine.source`。
- `shared_preferences` 现在是显式依赖（之前是传递依赖）。

## [0.1.0] - 2026-04-27

首次公开发布。

### 新增
- `NiumaPlayerController` —— 跨 iOS、Web、Android 的统一 Dart 侧 controller。
- `NiumaPlayerView` —— 开箱即用的 widget，会根据当前后端选择正确的渲染原语。
- `NiumaPlayerValue` 快照，自带互斥状态机
  （`idle / opening / ready / playing / paused / buffering / ended / error`）。
- 结构化错误模型：`PlayerError` + `PlayerErrorCategory`
  （`transient / codecUnsupported / network / terminal / unknown`）。
- 后端选择事件：`BackendSelected`、`FallbackTriggered`。
- iOS / Web 通过 `package:video_player` 路由（AVPlayer / `<video>`）。
- Android 原生插件，自带两种后端：
  - `ExoPlayerSession` —— 默认硬件加速路径
    （androidx.media3 1.4.1，含 HLS）。
  - `IjkSession` —— 基于 FFmpeg 的兜底路径，针对硬解码器不可用的设备。
- Android 上的 Try-Fail-Remember：原生侧把跑不动 ExoPlayer 的设备
  持久化标记到 `DeviceMemoryStore`（SharedPreferences），后续启动直接走 IJK。
  Dart 侧首次失败时会以 `forceIjk: true` 重试一次。
- `NiumaPlayerController.clearDeviceMemory()`，供"重置缓存"类 UI 调用。
- 循环不出现 `phase=ended` 闪烁 —— 原生侧在播完时直接重启，期间始终保持
  `playing` 状态。
- 依赖注入的 `BackendFactory` + `PlatformBridge`，支持纯 Dart 状态机测试
  （不需要 platform channel）。
- 14 个单元测试，覆盖 iOS / Web / Android happy path、retry success、
  retry failure、wall-clock 超时，以及 `DeviceMemory` 持久化。

[Unreleased]: https://github.com/axin789/niuma_player/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/axin789/niuma_player/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/axin789/niuma_player/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/axin789/niuma_player/releases/tag/v0.2.0
[0.1.0]: https://github.com/axin789/niuma_player/releases/tag/v0.1.0
