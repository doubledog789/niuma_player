# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-06-12

### Added

- **播放中自动保持屏幕常亮（wakelock）**：修复「播到一半自动熄屏」。
  `NiumaPlayerController` 在 playing 边沿自动保持 / 释放亮屏（暂停、结束、
  出错、dispose 都会释放），多实例（feed / 池）以进程级计数归并——任一在播
  即亮屏，全部停了才释放。Android 走 `FLAG_KEEP_SCREEN_ON`（窗口级、无需
  权限、退后台自动失效），iOS 走 `isIdleTimerDisabled`，web 无操作（浏览器
  播 `<video>` 自身防熄屏）。
  - 新增 `NiumaPlayerOptions.manageScreenWakelock`（默认 `true`；音频类
    业务想允许熄屏可置 `false`）
  - `PlatformBridge` 接口新增 `setKeepScreenOn(bool)`——**自定义
    `PlatformBridge` 实现方需补该方法**（0.x 下随 minor 发布）

## [0.3.0] - 2026-06-12

### Added

- **Android PlatformView（SurfaceView）渲染路径（opt-in）**：
  `NiumaPlayerOptions.useAndroidPlatformView = true` 时，Android 视频改由
  PlatformView（SurfaceView **原生缩放**）渲染，替代 Flutter Texture——从根
  上解决 Texture 路径的画质模糊，且不吃 `filterQuality` 的每帧采样开销。
  默认 `false`（行为与 0.2.x 完全一致），iOS / web 忽略此选项。
  - 原生侧新增 `PlayerSurfaceView` / `PlayerSurfaceViewFactory`（viewType
    `cn.niuma/player_surface`）；`NiumaPlayerView` 自动按 backend 选
    `AndroidView` 渲染分支
  - **surface 栈**：全屏路由 push 时第二个 SurfaceView 抢绑定、销毁时自动
    回退绑定到 inline 仍存活的 surface——退全屏不再输出到 dead Surface
    导致 codec 报错（OPPO Android 16 真机验证）
  - **prepare 不等 surface**：ExoPlayer / IJK 无 surface 即可 prepare
    （音频与状态机照常推进），surface 何时到画面何时出——feed 类
    「initialize → play → 才渲染激活页」的 mount 顺序不会死锁
  - 接入建议：详情页 / 单播放器开启收益最大；feed 每滑一条重建
    SurfaceView 有黑闪，建议维持默认 Texture。`NiumaPlayerView` 外请保持
    松约束（如包 `Center`），全屏路由建议快淡/瞬切（参考 example）
- `PlayerBackend.androidPlatformViewId` getter（默认 `null`）。

### Changed

- **`BackendFactory.createNative` 增加 `useAndroidPlatformView` 可选参数**——
  自定义 `BackendFactory` 实现方需同步该签名（0.x 下随 minor 发布）。

## [0.2.3] - 2026-06-07

### Changed

- **Android Texture 路径默认提一档画质**：`NiumaPlayerView` 新增
  `filterQuality` 参数，**默认 `FilterQuality.medium`**（双三次插值），替代
  Flutter `Texture` 硬编码的默认 `FilterQuality.low`（双线性）。修复反馈
  「视频有点花、不够高清」（多见于小米15 等大屏 / 高 DPI 现代机型，原默认 low
  在拉伸时糊感明显）。medium 在 2020+ 中端机以上无可感性能开销。极致性能场景
  （feed 多实例 + 低端机）可显式传 `FilterQuality.low` 降回旧默认。
  iOS 不受影响（`VideoPlayer` widget 内走 AVPlayer 原生 scaling）；web
  同样不受影响（浏览器直接缩放）。
- **下一步预告**：长期方案是把 Android 渲染改为 PlatformView（SurfaceView
  原生缩放），从根上去掉 Texture 路径的每帧 filterQuality 开销。已起
  `feat/android-platform-view` 分支，待真机回归后发 0.3.0。

## [0.2.2] - 2026-06-07

### Fixed

- **web rapid seek 卡 buffering**（Chrome/Firefox/Edge + hls.js）：`WebVideoBackend.seekTo`
  改为合并模式（latest-wins）——已有 seek 在路上时新调用只更新目标，待 `'seeked'`
  事件后再 fire 最新值，避免反复 seek 把 hls.js 的 `SourceBuffer` 卡进
  `updating=true` 永不释放、`'playing'` 永不来。配 3s 安全 timer 兜底（极端 case
  浏览器漏发 `'seeked'` 时也能解锁）。
- **Safari + hls.js 在已 buffered 区间 seek 后 phase 卡 buffering**：新增
  `'seeked'` 事件监听，按 video 真值兜底校准 phase（仅当 phase 为 buffering
  时纠正，playing/paused/ended/error 等明确状态保持不动）。修复多次快进快退
  后 UI spinner 不消失、底栏图标错乱、点击屏幕才恢复的 quirk。
- **`load()` 换源时残留 seek 状态**：换源即作废 `_isSeeking`/`_pendingSeek`/
  `_seekSafetyTimer`，避免锁跨源残留导致换源后第一次 seek 被吞。

## [0.2.1] - 2026-06-07

### Fixed

- **web HLS：hls.js xhrSetup 跳过浏览器 forbidden request headers**：
  `WebVideoBackend` 给 hls.js 配 `xhrSetup` 时把 `dataSource.headers` 里的
  `referer` / `host` / `origin` / `user-agent` / `cookie` 等浏览器禁止 JS 设置
  的请求头跳过，避免 hls.js 抛 `Refused to set unsafe header "referer"`
  并中断 HLS 加载。鉴权 token 等正常 header 仍透传。

### Changed

- **Android ijkplayer aar 砍掉 HEVC（H.265）软解兜底**，进一步精简：
  `libijkplayer.so` arm64 6.9→6.5 MiB / armv7 5.5→5.1 MiB，aar 7.6→7.0 MiB，
  对应 APK 单 arm64 ABI 省 ~400KB。decoder 仅留 `h264 / aac / aac_latm / mp3* +
  h264_mediacodec / mp3_mediacodec`；HEVC 解封装/parser/bsf 同步移除。
  **影响**：IJK 软解兜底路径不再支持 H.265；Android ExoPlayer 主路径仍可硬解
  H.265，仅在「ExoPlayer 翻车 + 视频是 H.265」双重场景才会播不了。点播
  mp4+HLS（主流 H.264 编码）不受影响。编译配置见
  `android/scripts/compile/modules/module-niuma-ff7-slim.sh`。

## [0.2.0] - 2026-06-05

### Added

- **`NiumaPlayerController.load(NiumaMediaSource)`** 原地换源（+ `PlayerBackend`
  的 `supportsSourceSwap` / `load`）：复用当前 backend 换到新源。web 后端复用
  同一个 `<video>` 元素换 src（`supportsSourceSwap=true`），**保住 iOS Safari 的
  有声播放激活**——"滑到才知道下一条 URL"的 feed 可用一个 controller 反复换源，
  而非每条新建 controller、每条丢激活导致只能静音。backend 不支持换源时自动
  dispose + 重建兜底。
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
