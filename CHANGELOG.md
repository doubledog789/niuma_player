# Changelog

本项目所有显著变更都会记录在本文件中。

格式遵循 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/spec/v2.0.0.html)。

## [Unreleased]

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

[Unreleased]: https://github.com/axin789/niuma_player/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/axin789/niuma_player/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/axin789/niuma_player/releases/tag/v0.2.0
[0.1.0]: https://github.com/axin789/niuma_player/releases/tag/v0.1.0
