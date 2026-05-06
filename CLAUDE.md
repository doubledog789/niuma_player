# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目定位

`niuma_player` 是一个 Flutter 视频播放器 **SDK 包**（不是 app），通过统一 `NiumaPlayerController` API 覆盖 iOS / Android / Web 三端，并在 Android 上提供 ExoPlayer → IJK 自动回退。`example/` 是消费这个 SDK 的演示 app，不是被测主体。

## 常用命令

```bash
flutter pub get
flutter analyze              # 必须 clean，no warnings
flutter test                 # 跑全部 Dart 单测

# 单测
flutter test test/state_machine_test.dart
flutter test test/presentation/ad_scheduler_test.dart
flutter test --name 'fallback'           # 按测试名 substring 过滤

# 跑示例 app（消费 SDK 的真机/模拟器场景）
cd example && flutter run -d <device-id>

# 平台构建冒烟
flutter build apk --debug
flutter build ios --no-codesign
flutter build web
```

注意：`test/presentation/niuma_thumbnail_view_test.dart` 历史上有挂起问题（详见 claude-mem 记忆 obs 237-239）。如果 `flutter test` 整体卡住，先 `flutter test --exclude-tags=...` 或显式跳过该文件定位问题，不要直接砍测试。

## 架构关键路径（多文件视角）

### 1. 三层 backend 抽象 + DI 是测试可行的关键

```
NiumaPlayerController (lib/src/presentation/niuma_player_controller.dart)
  │ 持有 ValueNotifier<NiumaPlayerValue>，单一公共门面
  │
  ├─ BackendFactory (lib/src/domain/backend_factory.dart)            ← 接口
  │   └─ DefaultBackendFactory (lib/src/data/default_backend_factory.dart)
  │       ├─ VideoPlayerBackend  (iOS / Web → package:video_player)
  │       └─ NativeBackend       (Android → 自家 Kotlin plugin)
  │
  └─ PlatformBridge (lib/src/domain/platform_bridge.dart)            ← 接口
      └─ DefaultPlatformBridge (Wakelock / brightness / volume / orientation)
```

**为什么这么分**：`BackendFactory` + `PlatformBridge` 都是接口，所有 platform-channel / system 调用都走它们。`test/state_machine_test.dart` 直接 inject fake，**纯 Dart 状态机覆盖 100% 分支**，不需要 integration test 跑设备。改 controller 时务必维持这个边界——不要在 controller 里直接 `import 'dart:io'` 或调 `MethodChannel`。

### 2. Android Try-Fail-Remember

设备记忆 (`DeviceMemoryStore.kt`) 存在 **Kotlin 一侧** 的 `SharedPreferences`，不是 Dart。第一次播放失败时 Dart 调 `initialize(forceIjk: true)` 重试，原生侧把"该设备走 IJK"持久化。`NiumaPlayerController.clearDeviceMemory()` 是公开重置入口。

### 3. M7 编排层独立于 backend

`lib/src/orchestration/` 全部是纯 Dart 业务逻辑（多线路、retry policy、source middleware、续播、WebVTT 解析、弹幕 bucket loader / 轨道分配、auto-failover）。**只 import `flutter/foundation`**——没有 widget / painting / material / cupertino 依赖，可在纯 Dart 测试里跑。

凡是要触碰 `Widget` / `BuildContext` / `ImageProvider` 的"编排级"组件（广告调度 `ad/ad_schedule` / `ad/ad_scheduler`、缩略图缓存与 resolver、`ThumbnailFrame`）一律放 `lib/src/presentation/`——它们是 widget 适配器，不是纯业务规则。

### 4. M9 一体化 widget 与 9 个原子控件

`NiumaPlayer` (`lib/src/presentation/core/niuma_player.dart`) 是 90% 用户的入口；底层 9 个原子控件（`PlayPauseButton` / `ScrubBar` / `FullscreenButton` / ...）在 `lib/src/presentation/controls/` 单独导出，供需要自定义布局的业务直接拼装。`NiumaFullscreenPage` 通过 `InheritedWidget` marker 检测"是否已在全屏"决定 push/pop，**全屏路由透传** ad / theme / autoHide / loadingBuilder / errorBuilder / endedBuilder 等全部配置。

**原子控件命名**：业务侧推荐用 `Niuma*` 前缀 alias（`NiumaPlayPauseButton` / `NiumaScrubBar` 等）避免命名空间冲突。alias 在 `lib/src/control_aliases.dart` 定义，仍 export 原裸名向后兼容。

**反馈 UI builder slot**：`NiumaPlayer` 提供 `loadingBuilder` / `errorBuilder` / `endedBuilder` 三态可覆盖；不传走默认 `NiumaLoadingIndicator` / `NiumaErrorView` / `NiumaEndedView`（在 `lib/src/presentation/feedback/`）。`NiumaProgressThumb` 提供 `iconBuilder` slot 替换默认 niuma 表情。

### 5. M15 Cast 投屏（合并主包）

`lib/src/cast/` 含**协议抽象 + 实现**：抽象层 `CastService` / `CastDevice` / `CastSession` / `NiumaCastRegistry`，实现层 `cast/dlna/`（DLNA SSDP + SOAP 协议 9 文件）、`cast/airplay_cast_service.dart`（iOS 系统 RoutePicker）。

**自动注册**：`NiumaCastRegistry` 首次访问 `all()` / `byProtocolId()` 时 lazy 把 `DlnaCastService` + `AirPlayCastService` 加进来，业务方 0 配置就能用。仍可在 `main()` 里调 `register(...)` 注入自家协议（如 Chromecast）替代或补充。

之前是 federated 分包模式（`niuma_player_dlna` + `niuma_player_airplay` companion package）——0.x 起合并进主包，分包 sibling repo 已 orphaned。

### 6. iOS PiP 反射 hack 区

iOS PiP（`ios/Classes/NiumaPipPlugin.swift`）依赖反射 `video_player_avfoundation` 内部字段拿 AVPlayer：`registrar → flutterEngine → valuePublishedByPlugin → FVPVideoPlayerPlugin → playersByIdentifier → FVPVideoPlayer.player → AVPlayer`。

**关键防御**：`safeKVCValue` helper 在 KVC 之前用 ObjC runtime 检测 selector / property / ivar 存在，避免 `valueForUndefinedKey:` 抛 NSException 死锁线程；`NiumaObjCExceptionCatcher.{h,m}` 提供 `@try`/`@catch` 桥让 Swift 能抓 NSException（Swift 原生 `do-catch` 抓不到）。

**`unsafePipAutoBackgroundOnEnter`**：`NiumaPlayerOptions` 里的 opt-in flag（`@experimental`）。打开时 iOS 端调私有 API `UIApplication.shared.perform(Selector("suspend"))` 模拟 home 键让 PiP 立刻飘出。**启用后 host app 无法过 App Store 审核**——文档里 `lib/src/presentation/core/niuma_player_controller.dart` 字段 doc 第一行就大字 `**⚠️ App Store 不兼容**`。Android 忽略此 flag。

## 公开 API 边界

`lib/niuma_player.dart` 是唯一的 barrel export。**任何 `lib/src/` 内部符号要对外暴露，必须显式 `export ... show ...;`** 这里。改这个文件等同于改 SDK 的公开 API：

- 删除/重命名导出符号 = breaking change，必须在 `CHANGELOG.md` 写 `BREAKING CHANGE:` 并 bump major-ish
- 新增导出 = minor bump
- 加 `lib/src/testing/` 下的 fake = patch（这些通过 `lib/testing.dart` 导出）

公开 Dart 符号必须写 `///` 文档注释（见 `analysis_options.yaml` 的 `flutter_lints` 严格档）。

## Commit / PR 约定

- **Conventional Commits**：`feat:` / `fix(android):` / `docs:` / `refactor:` / `test:` 等
- 提交前 `flutter analyze && flutter test` 必须双绿
- 改了公开 API → `CHANGELOG.md` 的 `## [Unreleased]` 区域加条目
- 修 bug 优先用 TDD：先写复现 bug 的测试，再让它通过（参考既有 `test/orchestration/auto_failover_test.dart` 风格）

## 平台原生入口

| 平台 | 入口文件 |
|---|---|
| Android | `android/src/main/kotlin/cn/niuma/niuma_player/NiumaPlayerPlugin.kt`（package: `cn.niuma.niuma_player`） |
| iOS | `ios/Classes/NiumaPlayerPlugin.swift` + `NiumaPipPlugin.swift` + `NiumaSystemPlugin.swift` + `NiumaAirPlayPlugin.swift` + `NiumaObjCExceptionCatcher.{h,m}` |

PiP 需要业务侧 `MainActivity.onPictureInPictureModeChanged` 调 `NiumaPlayerPlugin.reportPipModeChanged(...)` 回调进 SDK——这个在 README "M12 特性" 段有完整接入步骤，改 PiP 相关代码前先看那段。

**修 Swift / ObjC 后必须跑 `flutter build ios --no-codesign --debug` 验证编译过**——hot reload 不重 build native，直接让用户 cold start 测会反复浪费时间（曾踩过这坑）。

## `presentation/` 目录组织

```
lib/src/presentation/
├── core/         NiumaPlayer + Controller + View + Theme + popup_menu(part) + pip_lifecycle (6)
├── controls/     22 个原子控件（PlayPauseButton / ScrubBar / 等）
├── control_bar/  NiumaControlBar / Config / Button / FullscreenControlBar / button_override (6)
├── fullscreen/   NiumaFullscreenPage (1)
├── feedback/     NiumaLoadingIndicator / NiumaProgressThumb / NiumaErrorView / NiumaEndedView (4)
├── ad/           ad_schedule / ad_scheduler / NiumaAdOverlay (3)
├── cast/         NiumaCastButton / Overlay / PickerPanel (3)
├── danmaku/      NiumaDanmaku* + DanmakuSettingsPanel (5)
├── gesture/      NiumaGestureLayer / Hud (2)
├── thumbnail/    thumbnail_cache / frame / resolver / NiumaThumbnailView / ScrubPreview (5)
├── short_video/  5 个 NiumaShortVideo* widget
└── shared/       glass_card / video_time_format (2)
```

## 资源约定

`pubspec.yaml` 声明的 asset 目录：`assets/loading/` / `assets/player_controls/` / `assets/progress_thumbs/`。访问统一走 `NiumaSdkAssets` 常量（`lib/src/niuma_sdk_assets.dart`），**不要硬编码字符串路径**——`niuma_player.dart` 已经把这个类 re-export，业务和内部代码用同一个入口。
