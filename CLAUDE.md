# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目定位

`niuma_player` 是一个 **headless Flutter 视频播放内核 SDK 包**（不是 app）。0.1.0 起重定位：包**只导出播放内核**——`NiumaPlayerController` + 全部编排逻辑（orchestration：多线路 / auto-failover / retry / source middleware）+ 手势 / 全屏 headless controller + cast 值类型，覆盖 iOS / Android / Web 三端，Android 上 ExoPlayer → IJK 自动回退。**包内零 UI widget**：接入方用 `NiumaPlayerView` 渲染画面 + 监听 `controller.value` 自己拼 UI（或让 AI 生成）。`example/` 是消费内核的 **100 行最小 demo**（`example/lib/main.dart`），不是被测主体——核的测试在 `test/`。

**曾经的整套参考皮（88 文件 niuma_ui：一体化壳 / 原子控件 / 控件条 / 全屏页 / 弹幕引擎 + overlay / 广告调度 / 缩略图取帧 / DLNA + AirPlay 投屏协议与 UI / 短视频 / 主题）已移出本仓，保留在 git 历史**——需要时 `git log --all -- 'example/lib/niuma_ui/**'` 定位 commit，`git show <sha>:...` 取文件，或喂给 AI 当参考。它们不进 semver 契约。

**核 vs 参考皮边界**：判定规则——文件 import `package:flutter/material.dart` 或是纯 UI widget（`CustomPainter` / `InheritedWidget` / `StatefulWidget`）= chrome，不属于核。例外：`NiumaPlayerView`（渲染面，必须在核）、`NiumaFullscreenScope` marker + web 全屏路由协调契约（`lib/src/player/web_fullscreen_coordination.dart`，核的 `NiumaPlayerView` 要读它）。

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
NiumaPlayerController (lib/src/player/niuma_player_controller.dart)
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

### 2. Android 双内核（Exo 主 + IJK 兜底，选择完全显式）

Android 默认 ExoPlayer 硬解；`forceIjkOnAndroid: true` 强制 IJK 软解。首次 initialize 失败时 Dart 侧**当次会话内**自动用 IJK 重试一次（不落盘）；双内核都失败抛 `EngineFallbackFailure`（携带两段原始错误）。**设备记忆策略（Try-Fail-Remember）已移除**——一次失败不再影响后续会话。

IJK 原生产物来自 **GSY 官方 MavenCentral**（`io.github.carguo:gsyvideoplayer-java/-ex_so:11.3.0`，bilibili ijkplayer 0.8.8 + FFmpeg 4.3 全量：h264/h265/mp4/HLS，minSdk 21）。不要升到 12.x+（要求 minSdk 23）。历史上的自编 ShikinChen ff7.1 aar 及编译链已退役（git 历史可寻），别恢复——它有 fork 私货（show_first_frame 的 seek(0) hack）且高码率流软解不出帧。

### 3. 编排层独立于 backend

`lib/src/orchestration/` 全部是纯 Dart 业务逻辑（多线路 `multi_source`、auto-failover、retry policy、source middleware）。**只 import `flutter/foundation`**——没有 widget / painting / material / cupertino 依赖，可在纯 Dart 测试里跑。改这里务必维持这个边界。

### 4. headless controller：渲染面 + 手势 / 全屏

核**不含任何 UI widget**。唯一的 widget 是 `NiumaPlayerView`（`lib/src/player/niuma_player_view.dart`，一块无样式视频纹理 / `<video>` 表面）。播放控件全部由接入方监听 `controller.value` 自拼。

- `NiumaGestureController`（`lib/src/player/niuma_gesture_controller.dart`）：把拖动几何量映射成播放意图 + `GestureFeedbackState`（HUD 反馈状态），HUD widget 由接入方按 `feedback` ValueListenable 渲染。值对象 `GestureKind` / `GestureFeedbackState` / `GestureHudIcon` 在 `lib/src/domain/`，只产出语义 `hudIcon`（不带 `IconData`）。
- `NiumaFullscreenController`（`lib/src/player/niuma_fullscreen_controller.dart`）：进 / 退全屏的屏幕方向锁定 + system UI 切换 headless 编排。
- web 全屏协调：`web_fullscreen_coordination.dart` 的 `NiumaFullscreenScope` marker + `enterWebFullscreenRoute()` / `exitWebFullscreenRoute()` / `webFullscreenRouteCountListenable`——单 `<video>` 在 inline / 全屏路由间搬迁的契约，`NiumaPlayerView` 读它。

弹幕引擎 / 广告调度 / 缩略图取帧 / 一体化壳 / 原子控件 / 控件条 / 全屏页全部**不在核**——在 git 历史的参考皮里。

### 5. Cast 投屏：值类型留核、协议在 git 历史

`lib/src/cast/` 只剩**值类型**：`CastDevice` / `CastSession` / `CastConnectionState` / `CastEndReason`。`NiumaPlayerController.connectCast(session)` / `disconnectCast(...)` + `castSession` getter + `CastStarted` / `CastEnded` 事件依赖它们，故留核。

**协议实现（DLNA SSDP/SOAP、AirPlay RoutePicker）+ `CastService` SPI + `NiumaCastRegistry` + 投屏 UI 全部移出核**，在 git 历史的参考皮（`example/lib/niuma_ui/cast/`）里。接入方自实现 `CastService` 产出 `CastSession`，交给 `controller.connectCast(...)`。

### 6. iOS PiP 反射 hack 区

iOS PiP（`ios/Classes/NiumaPipPlugin.swift`）依赖反射 `video_player_avfoundation` 内部字段拿 AVPlayer：`registrar → flutterEngine → valuePublishedByPlugin → FVPVideoPlayerPlugin → playersByIdentifier → FVPVideoPlayer.player → AVPlayer`。

**关键防御**：`safeKVCValue` helper 在 KVC 之前用 ObjC runtime 检测 selector / property / ivar 存在，避免 `valueForUndefinedKey:` 抛 NSException 死锁线程；`NiumaObjCExceptionCatcher.{h,m}` 提供 `@try`/`@catch` 桥让 Swift 能抓 NSException（Swift 原生 `do-catch` 抓不到）。

**`unsafePipAutoBackgroundOnEnter`**：`NiumaPlayerOptions` 里的 opt-in flag（`@experimental`）。打开时 iOS 端调私有 API `UIApplication.shared.perform(Selector("suspend"))` 模拟 home 键让 PiP 立刻飘出。**启用后 host app 无法过 App Store 审核**——文档里 `lib/src/player/niuma_player_controller.dart` 字段 doc 第一行就大字 `**⚠️ App Store 不兼容**`。Android 忽略此 flag。

## 公开 API 边界

`lib/niuma_player.dart` 是唯一的 barrel export，0.1.0 起**只导出 headless 核**：backends / bridge / data_source / player_state（`NiumaPlayerValue` / `PlayerPhase` / 事件模型）/ `NiumaPlayerController` + `NiumaPlayerOptions` / `NiumaPlayerView` / 全部 orchestration（`NiumaMediaSource` / `MediaLine` / `MultiSourcePolicy` / `SourceMiddleware` 家族 / `RetryPolicy` / `AutoFailoverOrchestrator`）/ `NiumaGestureController` + 手势值对象（`GestureKind` / `GestureFeedbackState` / `GestureHudIcon`）/ `NiumaFullscreenController` + web 全屏协调（`NiumaFullscreenScope` / `enterWebFullscreenRoute` / `exitWebFullscreenRoute` / `webFullscreenRouteCountListenable`）/ cast 值类型（`CastDevice` / `CastSession` / `CastConnectionState` / `CastEndReason`）/ `formatVideoTime` / `NiumaSdkAssets` / `NiumaCapabilities`（媒体能力探测，如 supportsHevc）。**绝不导出任何 UI widget**——它们在 git 历史的参考皮里。

**任何 `lib/src/` 内部符号要对外暴露，必须显式 `export ... show ...;`** 这里。改这个文件等同于改 SDK 的公开 API：

- 删除/重命名导出符号 = breaking change，必须在 `CHANGELOG.md` 写 `BREAKING CHANGE:` 并 bump major-ish
- 新增导出 = minor bump

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

PiP 需要业务侧 `MainActivity.onPictureInPictureModeChanged` 调 `NiumaPlayerPlugin.reportPipModeChanged(...)` 回调进 SDK——README "平台原生接入" 段有完整接入步骤，改 PiP 相关代码前先看那段。

**修 Swift / ObjC 后必须跑 `flutter build ios --no-codesign --debug` 验证编译过**——hot reload 不重 build native，直接让用户 cold start 测会反复浪费时间（曾踩过这坑）。

## `lib/src/` 目录组织（headless 核，38 文件 7 块）

```
lib/src/
├── data/           三平台后端 + 平台桥
│                   default_backend_factory(.io/.web) / video_player_backend(iOS)
│                   / native_backend(Android ExoPlayer↔IJK) / web_video_backend
│                   / hls_detect / default_platform_bridge / _pip_event_bus
├── domain/         接口 + 状态值对象
│                   backend_factory / player_backend / platform_bridge / data_source
│                   / player_state(NiumaPlayerValue / PlayerPhase / 事件 / EngineFallbackFailure)
│                   / gesture_kind / gesture_feedback_state / gesture_hud_icon
├── orchestration/  纯 Dart 编排：multi_source / auto_failover / retry_policy
│                   / source_middleware / player_pool
├── capabilities/   媒体能力探测（supportsHevc，io/web 条件实现）
├── cast/           投屏值类型：cast_device / cast_session / cast_state（协议在 git 历史）
├── player/         controller + 渲染面 + headless controller
│                   niuma_player_controller / niuma_player_options / niuma_player_view
│                   / niuma_gesture_controller / niuma_fullscreen_controller
│                   / web_fullscreen_coordination(+_web_fullscreen_dom*)
│                   / pip_lifecycle_observer / video_time_format
└── niuma_sdk_assets.dart  运行时 asset 常量（仅 web hls.js 路径）
```

**没有 `presentation/`、没有 `niuma_ui`、没有任何 UI widget。** 所有 UI（弹幕 / 广告 / 缩略图 / 投屏协议 / 一体化壳 / 原子控件 / 控件条 / 全屏页 / 短视频 / 主题）在 git 历史的参考皮里。

## 资源约定

`pubspec.yaml` 声明的 asset 目录 `assets/hls/`（vendored `hls.min.js`，web HLS 懒注入用）。访问统一走 `NiumaSdkAssets` 常量（`lib/src/niuma_sdk_assets.dart`），**不要硬编码字符串路径**——`niuma_player.dart` 已经把这个类 re-export，业务和内部代码用同一个入口。
