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

凡是要触碰 `Widget` / `BuildContext` / `ImageProvider` 的"编排级"组件（广告调度 `ad_schedule` / `ad_scheduler`、缩略图缓存与 resolver、`ThumbnailFrame`）一律放 `lib/src/presentation/`——它们是 widget 适配器，不是纯业务规则。

### 4. M9 一体化 widget 与 9 个原子控件

`NiumaPlayer` (lib/src/presentation/niuma_player.dart) 是 90% 用户的入口；底层 9 个原子控件（`PlayPauseButton` / `ScrubBar` / `FullscreenButton` / ...）在 `lib/src/presentation/controls/` 单独导出，供需要自定义布局的业务直接拼装。`NiumaFullscreenPage` 通过 `InheritedWidget` marker 检测"是否已在全屏"决定 push/pop，**全屏路由透传** ad / theme / autoHide 等全部配置。

### 5. 跨包 federated 插件（M15 Cast）

`lib/src/cast/` 仅定义抽象（`CastService` / `CastDevice` / `CastSession`）。具体 DLNA / AirPlay / Chromecast 实现走 companion package（如 `niuma_player_dlna`），业务侧 `NiumaCastRegistry.register(...)` 接入。**不要在主包里加任何具体协议实现**。

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
| iOS | `ios/Classes/NiumaPlayerPlugin.swift` + `NiumaPipPlugin.swift` + `NiumaSystemPlugin.swift` |

PiP 需要业务侧 `MainActivity.onPictureInPictureModeChanged` 调 `NiumaPlayerPlugin.reportPipModeChanged(...)` 回调进 SDK——这个在 README "M12 特性" 段有完整接入步骤，改 PiP 相关代码前先看那段。

## 资源约定

`pubspec.yaml` 声明的 asset 目录：`assets/loading/` / `assets/player_controls/` / `assets/progress_thumbs/`。访问统一走 `NiumaSdkAssets` 常量（`lib/src/niuma_sdk_assets.dart`），**不要硬编码字符串路径**——`niuma_player.dart` 已经把这个类 re-export，业务和内部代码用同一个入口。
