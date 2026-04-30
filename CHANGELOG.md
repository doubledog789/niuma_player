# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-04-30

### Added (M8 — 缩略图 VTT)
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

### Added (M7 — orchestration layer)
- `NiumaMediaSource` (`single` + `lines` factories) carrying `MediaLine` entries with `MediaQuality`.
- `MultiSourcePolicy.autoFailover(maxAttempts: 1)` (default) / `MultiSourcePolicy.manual()`.
- `NiumaPlayerController.switchLine(id)` with `LineSwitching` / `LineSwitched` /
  `LineSwitchFailed` events; preserves position + play state across the switch.
- `AutoFailoverOrchestrator` — picks the next priority line on `network` / `terminal`
  errors only (codec-unsupported short-circuits); priority is ascending (lower number
  = tried first). **Note**: M7 ships this as a standalone helper; the controller
  does not yet consume it. Wiring `MultiSourcePolicy` into the controller is
  deferred to a follow-up milestone.
- `SourceMiddleware` abstract + `HeaderInjectionMiddleware` + `SignedUrlMiddleware`
  + `runSourceMiddlewares` pipeline; runs before backend init, on switchLine, and on
  retry — guarantees fresh headers / freshly signed URLs each time.
- `NiumaPlayerController` constructor now accepts an optional `middlewares`
  parameter; pipeline executes once before the backend is built.
- `ResumeStorage` (abstract) + `SharedPreferencesResumeStorage` (default) +
  `ResumePolicy` + `ResumeBehaviour` (`auto` / `askUser` / `disabled`) +
  `ResumeOrchestrator` (read on init, periodic save, ended-clear, dispose final-save).
- `RetryPolicy.smart()` / `.exponential()` / `.none()`. `NiumaPlayerController`
  applies the policy around `backend.initialize()` (default `smart` retries
  `network` + `transient` up to 3 attempts with exponential 1s → 10s backoff);
  the existing forceIjk Try-Fail-Remember fallback continues underneath.
- `AdCue` + `AdController` contract + `NiumaAdSchedule` + `MidRollAd` +
  `MidRollSkipPolicy` + `PauseAdShowPolicy`.
- `AdSchedulerOrchestrator` covering preRoll (idle→ready), midRoll (with
  `skipIfSeekedPast` default), pauseAd (with `oncePerSession` default + `cooldown`
  option), postRoll (phase=ended). Note: `AdControllerImpl` exists internally to
  enforce `minDisplayDuration` before allowing dismiss, but is **not** part of
  the M7 public API — the orchestrator only signals `activeCue` for now and
  controller wiring through `cue.builder` lands in M9.
- `AnalyticsEvent` sealed hierarchy (`AdScheduled` / `AdImpression` / `AdClick` /
  `AdDismissed`) + `AnalyticsEmitter` typedef hook.
- Public test doubles via `package:niuma_player/testing.dart`:
  `FakeResumeStorage`, `FakeAnalyticsEmitter`.

### Changed
- `NiumaPlayerController` first-arg type: `NiumaDataSource` → `NiumaMediaSource`.
  Use `NiumaPlayerController.dataSource(ds)` factory for the single-source case
  (drop-in replacement for old call sites). The `dataSource` getter still returns
  `source.currentLine.source`.
- `shared_preferences` is now an explicit dependency (was previously a transitive).

## [0.1.0] - 2026-04-27

First public release.

### Added
- `NiumaPlayerController` — unified Dart-side controller for iOS, Web, and Android.
- `NiumaPlayerView` — drop-in widget that picks the right rendering primitive
  for the active backend.
- `NiumaPlayerValue` snapshot with phase-exclusive state machine
  (`idle / opening / ready / playing / paused / buffering / ended / error`).
- Structured error model: `PlayerError` + `PlayerErrorCategory`
  (`transient / codecUnsupported / network / terminal / unknown`).
- Backend selection events: `BackendSelected`, `FallbackTriggered`.
- iOS / Web routing through `package:video_player` (AVPlayer / `<video>`).
- Android native plugin with two backends:
  - `ExoPlayerSession` — default hardware-accelerated path
    (androidx.media3 1.4.1, including HLS).
  - `IjkSession` — FFmpeg-based rescue path for devices without working
    hardware decoders.
- Try-Fail-Remember on Android: native side persistently marks devices
  that can't run ExoPlayer in `DeviceMemoryStore` (SharedPreferences) and
  goes straight to IJK on subsequent launches. Dart side does a single
  retry with `forceIjk: true` on first-attempt failure.
- `NiumaPlayerController.clearDeviceMemory()` for "reset cache" UI flows.
- Loop without `phase=ended` flicker — native restarts on completion
  while staying in `playing`.
- Dependency-injected `BackendFactory` + `PlatformBridge` for pure-Dart
  state-machine tests (no platform channels).
- 14 unit tests covering iOS / Web / Android happy path, retry success,
  retry failure, wall-clock timeout, plus `DeviceMemory` persistence.

[Unreleased]: https://github.com/axin789/niuma_player/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/axin789/niuma_player/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/axin789/niuma_player/releases/tag/v0.2.0
[0.1.0]: https://github.com/axin789/niuma_player/releases/tag/v0.1.0
