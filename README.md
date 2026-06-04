# niuma_player

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/flutter-%E2%89%A53.10-blue)](https://flutter.dev)

**Headless Flutter 视频播放内核**——**iOS / Android / Web 三端**统一 controller API，附带纯逻辑播放编排（多线路自动 failover / 切换失败回滚 / retry policy / source middleware）以及手势、全屏的 headless controller。

> **本包不提供播放器控件皮肤。** 接入方用无样式渲染面 `NiumaPlayerView` 渲染画面 + 监听 `controller.value`（`ValueNotifier<NiumaPlayerValue>`）自己拼控件，或让 AI 按需生成。曾经的整套参考皮（一体化播放器壳、原子控件、控件条、全屏页、弹幕 / 广告 / 缩略图 / 投屏 UI、短视频、主题，共 88 文件）保留在 **git 历史**里——需要时用 `git log` / `git show` 捞，或喂给 AI 当参考。

---

## 目录

- [设计哲学：headless 内核](#设计哲学headless-内核)
- [平台兼容](#平台兼容)
- [安装](#安装)
- [最小用法](#最小用法)
- [核心 API 速查](#核心-api-速查)
- [平台原生接入](#平台原生接入)
- [Web 平台已知限制](#web-平台已知限制)
- [文档](#文档)

---

## 设计哲学：headless 内核

niuma_player 只做一件事：**把视频在三端可靠地播起来，并把播放状态以统一的 `NiumaPlayerValue` 暴露出来**。它不替你决定 UI 长什么样。

- 播放引擎、状态机、错误分类、多线路 failover、retry、source middleware 都在核里，是稳定的 semver 契约。
- 画面渲染走一个无样式的 `NiumaPlayerView`（一块视频纹理 / `<video>` 表面）。
- 所有控件——播放按钮、进度条、全屏、弹幕、投屏面板、缩略图预览——**由接入方自己写**：监听 `controller.value` 拿 phase / position / duration / size / error，调 `controller.play()` / `pause()` / `seekTo()` 等驱动。

这样换来的好处：

- SDK 体积小、依赖少，不把一套别人的视觉强加给你。
- UI 完全是你自家的设计系统，不用跟 SDK 的主题打架。
- 复杂控件可以让 AI 按你的 design token 生成，或从 git 历史里的参考皮捞现成实现改造。

**需要参考实现？** 整套老的参考皮（bili 风长视频壳 / 抖音风短视频 / 弹幕引擎 + overlay / DLNA + AirPlay 投屏协议与 UI / 缩略图取帧 / 广告调度 / 主题）都在 git 历史里。`git log --all -- 'example/lib/niuma_ui/**'` 找到那个 commit，`git show <sha>:example/lib/niuma_ui/...` 取文件即可。

### 投屏（Cast）说明

核里只保留**投屏的值类型 + 协调入口**：`CastDevice` / `CastSession` / `CastConnectionState` / `CastEndReason`，加上 `controller.connectCast(...)` / `controller.disconnectCast(...)` 和 `CastStarted` / `CastEnded` 事件。**具体协议实现（DLNA SSDP/SOAP、AirPlay RoutePicker）和投屏 UI 不在核里**——在 git 历史的参考皮中（`example/lib/niuma_ui/cast/`），接入方按需捞取自维护，并把自家 `CastService` 实现产出的 `CastSession` 交给 `controller.connectCast(...)`。

---

## 平台兼容

| 平台 | 后端引擎 | HLS | PiP | 投屏 |
|---|---|:-:|:-:|:-:|
| **iOS** | AVPlayer (`video_player`) | ✅ 原生 | ✅（反射 AVPlayer 接 `AVPictureInPictureController`） | 值类型 + 协调在核；AirPlay 协议在参考皮 |
| **Android** | ExoPlayer ↔ IJK（自家 plugin，IJK 已升 FFmpeg 7.1.1 slim 重编） | ✅ 原生 | ✅（业务侧 1 行回调接入） | 值类型 + 协调在核；DLNA 协议在参考皮 |
| **Web** | `<video>` + 按需 hls.js | ✅（Safari 原生 / Chrome·Firefox·Edge 走 hls.js 懒注入） | ⚠️ 浏览器无可靠程序化 API | ⚠️ 浏览器无可靠程序化 API |

Web 端基于 `package:web`，**wasm-ready**（可随 `flutter build web --wasm` 编译）。

---

## 安装

```yaml
dependencies:
  niuma_player:
    git:
      url: https://github.com/axin789/niuma_player.git
      ref: main
```

```bash
flutter pub get
```

外部依赖只有 5 个：`video_player`（iOS AVPlayer）、`web`（Web 后端）、`plugin_platform_interface`、`meta`、`clock`；另有 Flutter SDK 自带的 `flutter_web_plugins`。

---

## 最小用法

下面这段就是 `example/lib/minimal_player/minimal_player.dart` 的核心：`NiumaPlayerView` 渲染画面，`ValueListenableBuilder<NiumaPlayerValue>` 监听状态自己拼播放/暂停 + 进度条 + 时间。

```dart
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final NiumaPlayerController _c;

  @override
  void initState() {
    super.initState();
    _c = NiumaPlayerController.dataSource(
      NiumaDataSource.network('https://example.com/video.mp4'),
    )..initialize();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(aspectRatio: 16 / 9, child: NiumaPlayerView(_c)),
        ValueListenableBuilder<NiumaPlayerValue>(
          valueListenable: _c,
          builder: (context, value, _) {
            final maxMs = value.duration.inMilliseconds;
            return Row(
              children: [
                IconButton(
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: value.isPlaying ? _c.pause : _c.play,
                ),
                Expanded(
                  child: Slider(
                    value: value.position.inMilliseconds
                        .clamp(0, maxMs)
                        .toDouble(),
                    max: maxMs > 0 ? maxMs.toDouble() : 1,
                    onChanged: maxMs > 0
                        ? (v) =>
                            _c.seekTo(Duration(milliseconds: v.round()))
                        : null,
                  ),
                ),
                Text('${formatVideoTime(value.position)} / '
                    '${formatVideoTime(value.duration)}'),
              ],
            );
          },
        ),
      ],
    );
  }
}
```

完整可运行版本见 [`example/lib/minimal_player/minimal_player.dart`](example/lib/minimal_player/minimal_player.dart)。更详细的接入步骤见 [`doc/getting-started.md`](doc/getting-started.md)，全部公开符号见 [`doc/api-reference.md`](doc/api-reference.md)。

---

## 核心 API 速查

### NiumaPlayerController

```dart
// 单 source 便捷构造：
final c = NiumaPlayerController.dataSource(
  NiumaDataSource.network('https://example.com/video.mp4'),
);

// 多线路 / 自定义 policy 构造：
final c = NiumaPlayerController(
  source,                                  // NiumaMediaSource
  middlewares: const [],                   // SourceMiddleware 流水线
  retryPolicy: const RetryPolicy.smart(),
  options: const NiumaPlayerOptions(),
);

await c.initialize();
c.play();
c.pause();
c.seekTo(const Duration(seconds: 30));
c.setPlaybackSpeed(1.5);
c.setVolume(0.8);
await c.dispose();

c.value;                  // 当前 NiumaPlayerValue（NiumaPlayerController extends ValueNotifier）
c.events;                 // Stream<NiumaPlayerEvent>
c.activeLineId;           // 当前线路 id
```

### NiumaPlayerValue（监听这个拼 UI）

```dart
value.phase;                       // PlayerPhase: idle/opening/ready/playing/paused/buffering/ended/error
value.position;                    // 当前位置 Duration
value.duration;                    // 总时长 Duration
value.bufferedPosition;            // 已缓冲位置
value.size;                        // 视频自然分辨率 Size
value.playbackSpeed;               // double
value.error;                       // PlayerError?（phase==error 时非 null）
value.isInPictureInPicture;        // 是否在 PiP
value.isPictureInPictureSupported; // 设备是否支持 PiP
value.isPlaying;                   // phase == playing
value.initialized;                 // 已 init 且不在 opening
value.hasError;                    // phase == error
```

### 多线路 + failover

```dart
final source = NiumaMediaSource.lines(
  lines: [
    MediaLine(id: 'cdn1', label: '线路 1', priority: 0,
        source: NiumaDataSource.network('https://cdn1/v.m3u8')),
    MediaLine(id: 'cdn2', label: '线路 2', priority: 1,
        source: NiumaDataSource.network('https://cdn2/v.m3u8')),
  ],
  defaultLineId: 'cdn1',
);

await c.switchLine('cdn2');   // 业务主动切换；失败时按 options 静默回滚
```

`NiumaPlayerOptions` 默认 `autoFailoverOnInitialError: true`（默认线路 init 失败 → 按 priority 升序自动尝试下一条）与 `rollbackOnSwitchFailure: true`（主动切换失败 → 回滚原线路保留 position）。

### 全屏 / 手势 headless controller

```dart
// 全屏：朝向锁定 + system UI 切换的纯编排，UI 由你自己摆
final fs = NiumaFullscreenController(...);

// 手势：把拖动几何量映射成播放意图 + HUD 反馈状态
final gesture = NiumaGestureController(...);
gesture.feedback;   // ValueListenable<GestureFeedbackState?>，监听它渲染你自家 HUD
```

Web 单 `<video>` 在 inline / 全屏路由间搬迁的协调契约：`NiumaFullscreenScope` + `enterWebFullscreenRoute()` / `exitWebFullscreenRoute()` / `webFullscreenRouteCountListenable`。

### 投屏（Cast）

```dart
// 你的 CastService 实现产出一个 CastSession，交给核：
await c.connectCast(session);
await c.disconnectCast(reason: CastEndReason.userCancelled);
c.castSession;            // ValueListenable<CastSession?>

c.events.listen((e) {
  if (e is CastStarted) { /* e.device: CastDevice */ }
  if (e is CastEnded)   { /* e.reason: CastEndReason */ }
});
```

### 事件流

```dart
c.events.listen((e) {
  if (e is BackendSelected) { /* iOS / Android / Web 选定 */ }
  if (e is FallbackTriggered) { /* Android ExoPlayer → IJK */ }
  if (e is LineSwitching) {}
  if (e is LineSwitched) {}
  if (e is LineSwitchFailed) { /* 即使已回滚也会 emit，供业务上报 */ }
  if (e is PipModeChanged) {}
});
```

---

## 平台原生接入

### iOS

`ios/Runner/Info.plist`：

```xml
<!-- 允许 HTTP 视频源（HTTPS 不需要） -->
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsArbitraryLoads</key><true/></dict>

<!-- PiP 后台音频继续播 -->
<key>UIBackgroundModes</key>
<array><string>audio</string></array>
```

PiP 不需要额外原生代码——核内部反射 `video_player_avfoundation` 拿 AVPlayer 接 `AVPictureInPictureController`。

### Android

`android/app/src/main/AndroidManifest.xml`：

```xml
<uses-permission android:name="android.permission.INTERNET"/>

<activity
    android:supportsPictureInPicture="true"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode">
```

`MainActivity.kt`——必须接 PiP 回调，否则核收不到进/退 PiP 事件：

```kotlin
import android.content.res.Configuration
import cn.niuma.niuma_player.NiumaPlayerPlugin
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration?,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        NiumaPlayerPlugin.reportPipModeChanged(isInPictureInPictureMode)
    }
}
```

### Web

`web/index.html` `<head>` 内（PWA 全屏覆盖 notch / home indicator）：

```html
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
<meta name="theme-color" content="#000000">
```

HLS 在 Chrome / Firefox / Edge 走核内置的 vendored `hls.js`（`assets/hls/hls.min.js`），仅当播放 HLS 源且非 Safari 时运行时懒注入 `<script>`；纯 mp4 页面不加载任何额外 JS。Safari 走浏览器原生 HLS。

---

## Web 平台已知限制

- **PiP / 投屏**：浏览器没有可靠的程序化 API，核在 web 上不提供这两个能力（自家 UI 应隐藏对应入口）。
- **`SystemChrome.setPreferredOrientations`**：web 平台 no-op，无法程序化锁方向。竖屏 viewport 放横屏视频时，建议自家 UI 浮一个"旋转屏幕"提示。
- **iOS Safari `<video>.volume` setter 只读**：核同步设 `muted` 解决"按钮静音不生效"。
- **iOS Safari `videoWidth/Height` 滞后**：`onLoadedMetadata` 时尺寸可能仍是 0，核在 `onPlaying` / `onTimeUpdate` 时 retry 同步 `value.size`。

---

## 文档

- [`doc/getting-started.md`](doc/getting-started.md) — 接入步骤
- [`doc/api-reference.md`](doc/api-reference.md) — 公开符号速查
- [`CHANGELOG.md`](CHANGELOG.md) — 版本变更
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — 贡献指南

---

## 许可证

Apache 2.0 — 见 [LICENSE](LICENSE)。
