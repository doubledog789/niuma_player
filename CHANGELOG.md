# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **web 全屏分流原语**（`NiumaWebFullscreenMode` / `webFullscreenMode` /
  `requestBrowserFullscreen` / `exitBrowserFullscreen` / `onBrowserFullscreenChange`，
  自 `web_fullscreen_coordination`）：把「浏览器全屏能力检测（安全读
  `fullscreenEnabled`、绕开 iOS Safari `undefined` 抛 `TypeError`）+ 画布真全屏
  进出 + 全屏状态监听」收进核，接入方据 `webFullscreenMode` 分流即可、不必碰
  DOM：`nativeVideoElement`（iOS Safari，走系统 player 全屏）/ `browserElement`
  （Chrome 等，走画布真全屏 + 自家全屏页）/ `notWeb`。
- **`NiumaPlayerController.setWebNativeControls(bool)`**（+ `PlayerBackend` 同名
  方法）：web-only，开 / 关底层 `<video>` 的浏览器原生控件。iOS Safari 上 Flutter
  自定义控件叠在 `<video>` 上会被浏览器吞、点不动，接入方可开原生控件兜底
  （播放 / 进度 / 全屏交给浏览器）。非 web backend 为空操作。

### Fixed

- **web video 被 DOM reparent 后自动续播**：`WebVideoBackend` 维护「播放意图」，
  video 因全屏搬迁等被浏览器自发暂停时，只要意图仍在播就自动续播——修复
  「Chrome 进全屏 / 退全屏后视频卡停」。用户主动 `pause()` 不受影响。
- **iOS Safari 退出原生全屏后自动恢复播放**：`WebVideoBackend.enterNativeFullscreen()`
  走 `webkitEnterFullscreen` 时记住进全屏前的播放态，监听 `webkitendfullscreen`，
  退出系统 player 后自动 `play()`（iOS 退出系统 player 默认会把 video 暂停）。
- **web `enterNativeFullscreen` 回归「浏览器原生全屏」语义**：`WebVideoBackend`
  此前把 `enterNativeFullscreen()` 实现成只翻一个 `NiumaPlayerView` 并不读取的
  内部 flag（等于 web 上调用它没有任何可见效果）；现在按 `PlayerBackend` 接口
  文档契约真正调用 `<video>.webkitEnterFullscreen()`（iOS Safari，进系统原生
  video player UI）/ `requestFullscreen()`（桌面 Safari / Chrome / Firefox /
  Android Chrome）。`exitNativeFullscreen()` 同步走 `webkitExitFullscreen` /
  `document.exitFullscreen()`。

## [0.1.0]

### BREAKING CHANGE: 重定位为 headless 播放内核

`niuma_player` 现在是**纯 headless 视频播放内核**——只导出
`NiumaPlayerController` + `NiumaPlayerView`（无样式渲染面）+ 全部纯 Dart 编排
逻辑（多线路 / auto-failover / retry policy / source middleware）+ 手势 / 全屏
的 **headless controller**（`NiumaGestureController` /
`NiumaFullscreenController`）+ cast 值类型。接入方监听
`controller.value`（`ValueNotifier<NiumaPlayerValue>`）自己拼 UI，或让 AI 按需
生成。

**所有 UI 全部出核，移入 git 历史**（曾经的 88 文件 niuma_ui 参考皮）：

- 一体化播放器壳 `NiumaPlayer` + 22 个原子控件 + 控件条（`NiumaControlBar` /
  `ControlBarConfig` / `ButtonOverride`）+ 全屏页 `NiumaFullscreenPage` + 三态
  反馈 UI + 主题 `NiumaPlayerTheme`。
- 弹幕引擎与 UI（`NiumaDanmakuController` / overlay / painter /
  settings panel / `DanmakuTrackAllocator`）。
- 广告调度（`NiumaAdSchedule` / `AdSchedulerOrchestrator` /
  `NiumaAdOverlay` + analytics 事件模型）。
- 缩略图取帧逻辑与 widget（`ThumbnailFrame` / `WebVttParser` /
  `ThumbnailResolver` / `NiumaThumbnailView` / `NiumaScrubPreview`）。
- 投屏协议实现与 UI（DLNA SSDP/SOAP、AirPlay RoutePicker、
  `NiumaCastRegistry` / `CastService` SPI、cast 按钮 / picker 面板）。
- 短视频整套（5 个 `NiumaShortVideo*` widget + `NiumaShortVideoTheme`）。
- 本地续播（resume position）。

需要参考实现：`git log --all -- 'example/lib/niuma_ui/**'` 定位 commit，
`git show <sha>:example/lib/niuma_ui/...` 取文件，或喂给 AI 当参考。

**核仍保留的 cast 值类型**：`CastDevice` / `CastSession` /
`CastConnectionState` / `CastEndReason`——`controller.connectCast(session)` /
`disconnectCast(...)` + `castSession` getter + `CastStarted` / `CastEnded`
事件依赖它们。具体协议由接入方实现 `CastService` 产出 `CastSession` 交给核。

### Removed (依赖瘦身)

- 三方依赖从重定位前的一大堆砍到 5 个。移除 `shared_preferences`
  （Android 设备记忆改走 Kotlin 侧 `SharedPreferences`，Dart 不再依赖）/
  `flutter_svg`（UI 出核）/ `http`（核不再 fetch VTT，缩略图取帧出核）。

### Changed (平台引擎)

- **Web** 后端从已废弃的 `dart:html` 迁到 `package:web` + `dart:js_interop`，
  **wasm-ready**——可随 `flutter build web --wasm` 编译。
- **Android** IJK 升级到 **FFmpeg 7.1.1** slim 重编（vendored `.aar`），
  ExoPlayer ↔ IJK 自动回退路径不变。

### Changed (example)

- `example/` 精简为 **100 行最小 demo**（`example/lib/main.dart`）：
  `NiumaPlayerController.dataSource` + `NiumaPlayerView` +
  `ValueListenableBuilder<NiumaPlayerValue>` 自拼 play/pause + 进度 + 时间。
  原 8 个 demo 页随参考皮移入 git 历史。

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
