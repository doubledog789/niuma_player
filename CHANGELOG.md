# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

### BREAKING CHANGE: 重定位为 headless 播放内核

`niuma_player` 现在只导出播放内核：`NiumaPlayerController` + 全部编排逻辑
（多线路 / 续播 / retry / source middleware / auto-failover / 弹幕引擎 /
缩略图轨道）+ 手势 / 全屏 / 弹幕的 **headless controller**
（`NiumaGestureController` / `NiumaFullscreenController` /
`NiumaDanmakuController`）+ cast 抽象（`CastService` 接口除外，见下）。

所有 UI widget（`NiumaPlayer` 一体化、22 个原子控件、控件条、全屏页、反馈
态、弹幕 / 广告 / 缩略图 / cast / 短视频 UI、主题）已移出包，作为**可拷贝参考
皮**存放于 `example/lib/niuma_ui/`，不再进 semver 契约。

**新增导出**：

- `NiumaGestureController`——手势几何量 → 播放意图 + HUD 反馈的 headless 编排
  器（参考皮的 gesture layer widget 只透传坐标）。
- `NiumaFullscreenController`——进 / 退全屏的屏幕方向锁定 + system UI 切换。
- `NiumaFullscreenScope` / `webFullscreenRouteCount` /
  `webFullscreenRouteCountListenable`——web 单 `<video>` 在 inline / 全屏间
  搬迁的协调契约（`NiumaPlayerView` 读，参考皮全屏页写）。
- `DanmakuTrackAllocator`（弹幕轨道分配）/ `formatVideoTime`（时长格式化纯
  函数）——参考皮渲染需要。

**移除导出**（全部移至 `example/lib/niuma_ui/`）：`NiumaPlayer` /
`NiumaPlayerConfigScope` / `NiumaPlayerTheme` / `NiumaFullscreenPage` /
`NiumaFullscreenControl` / 全部 feedback / 全部原子控件（裸名 + `Niuma*`
alias）/ 控件条全套 / `NiumaThumbnailView` / `NiumaScrubPreview` /
`ThumbnailFrame` 仍留（见下）/ 弹幕 overlay+scope+settings_panel / gesture
layer+hud / 全部 short_video + `NiumaShortVideoTheme` / 广告
（`NiumaAdOverlay` / `AdSchedulerOrchestrator` / `NiumaAdSchedule` 等）/
cast UI（`NiumaCastButton` / `NiumaCastOverlay` / `NiumaCastPickerPanel`）/
cast 协议实现（`DlnaCastService` / `AirPlayCastService` /
`NiumaCastRegistry` / `CastService` SPI）。

**仍留核**：`ThumbnailFrame`（`controller.thumbnailFor` 的返回类型）/ cast
抽象 `CastDevice` / `CastSession` / `CastConnectionState` / `CastEndReason`
（事件模型 `CastStarted` / `CastEnded` + `controller.connectCast` 依赖）。
`CastDevice.icon` 默认值从 `Icons.tv` 改为 `null`（核去 material 依赖，参考皮
渲染时 `device.icon ?? Icons.tv` 兜底）。

**迁移指南**：

1. 从 `example/lib/niuma_ui/` 拷贝所需子目录到你的工程，改 import 为本地相对
   路径；`NiumaPlayerController` 与编排 API 保持兼容。
2. cast（DLNA / AirPlay 协议 + UI）、广告、缩略图 widget 整块移入参考皮，接入
   方自维护——拷 `niuma_ui/cast/`（含 DLNA SSDP / SOAP 9 文件）即获完整投屏
   能力。
3. 参考 `example/lib/niuma_ui/niuma_ui.dart` 皮 barrel 了解可拷贝符号清单；各
   demo 页是活的拷贝示范。

### Added (此前 Unreleased)

- `NiumaFullscreenControl` extension on `NiumaPlayerController` exposing
  `enterFullscreen(context)` / `exitFullscreen(context)` /
  `toggleFullscreen(context)` / `isInFullscreen(context)`. 该扩展随全屏页一起
  移入参考皮（`example/lib/niuma_ui/fullscreen/`）。

## [0.0.4] - 2026-05-25

### Fixed

- Vendored the custom-compiled `ijkplayer` `.aar` (13 MB) into git and the
  published package. It was previously git-ignored and fetched by a download
  script whose release URL no longer exists, so neither git nor pub.dev
  consumers received the binary and every Android build failed to resolve
  `tv.danmaku.ijk:ijkplayer`. The aar now ships under `android/localmaven/`,
  so Android builds work out of the box. Removed the dead download script.

## [0.0.3] - 2026-05-09

### Fixed

- Bumped `video_player` lower bound to `>=2.10.0`. The 2.8.0 lower bound
  failed pana downgrade analysis because `VideoPlayerController.playerId`
  (used by the iOS PiP bridge to map a Flutter texture id to its native
  AVPlayer instance) was only added in `video_player 2.10.0`.
- Declared web platform support in `pubspec.yaml` plugin manifest with a
  no-op `NiumaPlayerWebRegistrar` stub. Web behavior is implemented in pure
  Dart via conditional imports (`WebVideoBackend`); the stub exists only so
  Flutter's web plugin discovery can satisfy the platform declaration.
- Trimmed `CHANGELOG.md` to public 0.0.x entries only. The full
  internal-preview history (0.1.0 through 0.9.1) — which is mostly Chinese
  prose and was tripping pub.dev's non-ASCII content check — moved to
  [`doc/CHANGELOG_zh_internal_preview.md`](doc/CHANGELOG_zh_internal_preview.md).

## [0.0.2] - 2026-05-09

### Fixed

- Replaced `dart:js_util` (removed in Dart SDK 3.11) with `dart:js_interop` /
  `dart:js_interop_unsafe` in `web_video_backend.dart`. Fixes pub.dev pana
  static analysis failure that previously zeroed out platform support score.
- Shortened pubspec.yaml description to fit pub.dev 60-180 char limit.
- Added English-language summaries to `CHANGELOG.md`.

## [0.0.1] - 2026-05-09

**First public pub.dev release.** Version reset from internal-preview 0.9.x
to 0.0.1 as the inaugural public SDK version. Feature set equivalent to
internal 0.9.1, including:

- 3-tier backend abstraction (VideoPlayerBackend for iOS/Web, NativeBackend
  for Android) plus Android Try-Fail-Remember device memory.
- Orchestration layer (multi-line, retry policy, source middleware, resume
  position, WebVTT thumbnails, danmaku bucket loader, auto-failover).
- All-in-one `NiumaPlayer` widget plus 22 atomic control widgets and a
  configurable `NiumaControlBar`.
- Picture-in-Picture (iOS via reflection bridge, Android native).
- Cast: DLNA and AirPlay auto-registration via `NiumaCastRegistry`.
- Feedback UI builder slots: `loadingBuilder`, `errorBuilder`, `endedBuilder`.
- Short-video player with TikTok-style gestures, scrubber, speed control.
- Web fullscreen, cross-backend swap coordination, iOS Safari quirk fixes.

For the detailed history of internal-preview iterations leading up to this
release (0.1.x through 0.9.1), see
[`doc/CHANGELOG_zh_internal_preview.md`](doc/CHANGELOG_zh_internal_preview.md)
(Chinese).
