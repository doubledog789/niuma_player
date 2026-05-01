# niuma_player

[![CI](https://github.com/niuma/niuma_player/actions/workflows/ci.yml/badge.svg)](https://github.com/niuma/niuma_player/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/flutter-%E2%89%A53.10-blue)](https://flutter.dev)

生产级 Flutter 视频播放器，提供跨 iOS / Android / Web 三端统一的 `controller.value` API，并在 Android 上内置 ExoPlayer → IJK 自动回退路径，让那些无法硬解的旧机型 / 华为机型也能正常播放。

## 为什么造这个轮子

`package:video_player` 是显而易见的起点，但在 Android 上有两个广为人知的问题会卡到企业级应用：

1. **旧机型 / 华为机型硬解码器缺位** —— 黑屏，无报错，无法播放。
2. **受限网络下的 HLS** —— ExoPlayer 的 HLS 实现在某些 CDN 上会卡住，唯一切实可行的兜底方案是基于 FFmpeg 的播放器，比如 IJK。

`niuma_player` 透明地解决了这两个问题。Android 上原生插件优先尝试 ExoPlayer；如果在第一帧之前失败，就切换到 IJK，并把设备指纹**记录**到持久化存储（`SharedPreferences`），后续每次启动都直接走 IJK —— 再也没有"昨天还能用今天就坏了"的玄学。

iOS 通过 `package:video_player` 走 AVFoundation。Web 通过 `package:video_player` 走浏览器的 `<video>` 元素。**三端共用同一套 Dart API。**

## 特性

- **一个 controller，三端通吃** —— `NiumaPlayerController` 在所有平台暴露相同的 `value`、事件和命令接口。
- **互斥的状态机** —— `playing`、`paused`、`buffering`、`ended`、`error` 互斥，不再需要靠 `isBuffering && !isPlaying && !isCompleted` 拼凑判断导致 UI 闪烁。
- **结构化错误** —— `PlayerErrorCategory`（`transient` / `codecUnsupported` / `network` / `terminal` / `unknown`），不需要正则匹配错误字符串。
- **Android 上 Try-Fail-Remember** —— 自动 ExoPlayer → IJK 回退，按设备持久化记忆，公开 `clearDeviceMemory()` 供"重置缓存"类 UI 调用。
- **循环不闪烁** —— 原生侧在播完时直接重启，不暴露 `phase=ended`，开了 `setLooping(true)` 的视频视觉上完全连续。
- **开箱即用的 widget** —— `NiumaPlayerView(controller)` 会根据当前后端自动选择正确的渲染原语（`VideoPlayer` / `Texture`）。
- **完全可测试** —— 依赖注入的 `BackendFactory` + `PlatformBridge` 让状态机可以在纯 Dart 单元测试里跑，不需要 platform channel。

## 平台支持

| 平台 | 后端 | HLS 支持 |
|---|---|---|
| iOS | AVPlayer（通过 `video_player`） | 原生（AVFoundation） |
| Android | ExoPlayer ↔ IJK（自家原生插件） | 原生（HLS 走 media3-exoplayer-hls；IJK 走 FFmpeg） |
| Web (Safari) | `<video>`（通过 `video_player`） | 原生 |
| Web (Chrome / Firefox / Edge) | `<video>`（通过 `video_player`） | **不内置** —— 如有需要请额外引入 `video_player_web_hls` |

## 安装

```yaml
dependencies:
  niuma_player:
    git:
      url: https://github.com/niuma/niuma_player.git
      ref: main
```

> 发布到 pub.dev 后，替换为 `niuma_player: ^0.1.0`。

## 5 行快速上手

```dart
final controller = NiumaPlayerController.dataSource(
  NiumaDataSource.network('https://example.com/big_buck_bunny.mp4'),
);
await controller.initialize();
controller.play();
// 在你的 widget 树里：
NiumaPlayerView(controller);
```

happy path 的全部 API 就这些。Try-Fail-Remember 机制、错误分类、后端选择事件都是可选的额外能力，你不需要主动碰它们。

## M7 特性（多线路、中间件、重试）

通过 `NiumaMediaSource.lines(...)` 把多个 CDN 镜像或不同清晰度的源装进一个 controller，再用 `switchLine` 在它们之间切换：

```dart
final controller = NiumaPlayerController(
  NiumaMediaSource.lines(
    lines: [
      MediaLine(id: 'cdn-a', label: 'CDN A',
        source: NiumaDataSource.network('https://a/video.m3u8')),
      MediaLine(id: 'cdn-b', label: 'CDN B',
        source: NiumaDataSource.network('https://b/video.m3u8'),
        priority: 1),
    ],
    defaultLineId: 'cdn-a',
  ),
  middlewares: const [
    HeaderInjectionMiddleware({'Authorization': 'Bearer ...'}),
  ],
  retryPolicy: const RetryPolicy.smart(),
);
await controller.initialize();
// 切换 CDN，位置和播放状态保留：
await controller.switchLine('cdn-b');
```

`SourceMiddleware` 在每次 backend 启动前都会跑——首次 initialize、`switchLine`、每次 retry——签名 URL 永远是新的。完整 demo 见 [`example/lib/multi_line_page.dart`](example/lib/multi_line_page.dart)。

## M8 特性（缩略图 VTT）

支持 WebVTT thumbnail track，让你给进度条悬浮预览图层取数。

```dart
final controller = NiumaPlayerController(
  NiumaMediaSource.single(
    NiumaDataSource.network('https://cdn.com/video.mp4'),
    thumbnailVtt: 'https://cdn.com/thumbnails.vtt',
  ),
);
await controller.initialize();

// 在进度条 hover 时调用
final frame = controller.thumbnailFor(const Duration(seconds: 30));
if (frame != null) {
  // frame.image 是 ImageProvider，frame.region 是 sprite 内裁剪 rect
  // 用 RawImage / Image + custom paint 渲染即可
}
```

支持的 VTT 格式（thumbnail 变种）：

```
WEBVTT

00:00.000 --> 00:05.000
sprite.jpg#xywh=0,0,128,72
```

特性：
- 自动 fetch + 解析；失败静默降级（视频不受影响）
- Sprite 图按 URL 去重 + LRU（默认 32 张上限，覆盖长视频典型 sprite 数）
- VTT URL 同样走 `SourceMiddleware`（HeaderInjection / SignedUrl）
- `controller.dispose()` 时清空 controller-local 引用并 `evict` 全局
  `PaintingBinding.imageCache` 中已解码的位图，避免 sprite 像素长期占住 RAM
- `NiumaThumbnailView(frame: ...)` 助手 widget：一行渲染缩略图（封装
  `ImageStream` 同步触发防御 + sprite crop）
- 不提供完整 hover 组件 —— `NiumaThumbnailView` 是渲染原子，进度条联动 hover
  / overlay 留给 M9

## M9 特性（UI overlay）

完整的 UI overlay 层——`NiumaPlayer` 一体化组件 + 主题 + 9 个原子控件 + 全屏 page + 广告 overlay + 进度条缩略图预览。

5 行起步（90% 用户用这个）：

```dart
final controller = NiumaPlayerController.dataSource(
  NiumaDataSource.network('https://example.com/video.mp4'),
  thumbnailVtt: 'https://example.com/thumbnails.vtt',
);
await controller.initialize();
controller.play();
// 在 widget 树里——一个组件就够了：
NiumaPlayer(controller: controller);
```

默认即拿到：

- B 站风格底部控件条（9 个控件 + 进度条）
- 进入播放后 5 秒自动隐藏控件，点击视频区切换显隐，暂停时强制显示
- 进度条拖动时上方悬浮 sprite 缩略图预览（M8 + M9 联动）
- 右下 fullscreen 按钮：通过内部 `InheritedWidget` marker 检测当前是
  否在全屏页内——在全屏页内时点击 pop 回原页面，不在时 push
  `NiumaFullscreenPage`（200ms 淡入 + landscape 锁定 + immersiveSticky）。
  **全屏路由透传**外层全部配置（`adSchedule` / `adAnalyticsEmitter` /
  `pauseVideoDuringAd` / `controlsAutoHideAfter` / `theme`，包括用
  `NiumaPlayerThemeData` 注入的 inherited 主题），全屏页内的
  `NiumaPlayer` 行为与原页一致。
- 可选广告 overlay：传 `adSchedule` 自动激活；广告事件包含 `AdImpression`
  / `AdClick` / `AdDismissed`，后者的 `reason` 涵盖 `userSkip` /
  `timeout` / `error`（cue.builder 异常时使用 `error` 而非冒充 timeout）

主题自定义（13 字段，全部可选）：

```dart
NiumaPlayerThemeData(
  data: const NiumaPlayerTheme(
    accentColor: Colors.deepPurpleAccent,
    scrubBarThumbRadiusActive: 12,
  ),
  child: NiumaPlayer(controller: controller),
);
```

需要更深度自定义时（控件位置 / 多视频面板 / 自定义动画），9 个原子控件全部公开 export，可自由拼装：

```dart
Column(children: [
  Row(children: [
    PlayPauseButton(controller: controller),
    TimeDisplay(controller: controller),
  ]),
  NiumaPlayerView(controller),
  ScrubBar(controller: controller),
  Row(children: [
    SpeedSelector(controller: controller),
    QualitySelector(controller: controller),
    VolumeButton(controller: controller),
    FullscreenButton(controller: controller),
  ]),
]);
```

完整 demo 见 [`example/lib/m9_default_demo_page.dart`](example/lib/m9_default_demo_page.dart) 和 [`example/lib/m9_custom_demo_page.dart`](example/lib/m9_custom_demo_page.dart)。

## M11 特性（弹幕 / barrage）

纯 Dart 渲染的弹幕层，三模式（scroll / topFixed / bottomFixed）+ 60s 桶 lazy load + 可选设置面板。零原生改动，三端一致。

接入只需 3 步：构造 `NiumaDanmakuController`，把它和 `NiumaPlayerController` 一起塞进 `NiumaPlayer`：

```dart
final danmaku = NiumaDanmakuController(
  loader: (start, end) async {
    // 60s 桶 lazy load，业务自己实现（你的 /api/danmaku/list 等）
    final raw = await api.fetchDanmaku(videoId, start, end);
    return raw.map((e) => DanmakuItem(
      position: Duration(seconds: e.pos),
      text: e.content,
      fontSize: e.size.toDouble(),
      color: Color(0xFF000000 | e.color),
      mode: DanmakuMode.scroll,
      pool: e.pool,        // 透传字段
      metadata: e.id,      // 业务任意字段
    )).toList();
  },
);

NiumaPlayer(
  controller: videoCtrl,
  danmakuController: danmaku,   // 传入即自动叠加 NiumaDanmakuOverlay
);

// 用户自己 send 后回包 echo 一条本地（SDK 不碰网络）
final pos = videoCtrl.value.position;
await api.sendDanmaku(pos, '我发的');
danmaku.add(DanmakuItem(position: pos, text: '我发的'));
```

**三种集成形态：**

1. **`NiumaPlayer` 自动接管**（默认）——传 `danmakuController` 即激活
2. **`NiumaDanmakuOverlay` 积木件**——自定义布局自己 Stack
3. **`NiumaDanmakuScope` + `DanmakuButton`**——独立布局也能让按钮可点

**设置面板**（可选）独立暴露：

```dart
showModalBottomSheet(
  context: context,
  builder: (_) => DanmakuSettingsPanel(danmaku: danmaku),
);
// 4 项：visible / fontScale / opacity / displayAreaPercent
```

**渲染策略：**

- CustomPainter 单 paint pass + TextPainter LRU cache（256 上限）
- 三模式 first-fit 轨道分配，满轨直接丢弃自然降密度（防 seek 后 backlog）
- 暂停 = 弹幕画面冻结（零代码，video.position 停推 painter 不 repaint）
- seek > 1s = 自动清空飞行 + 触发对应桶 lazy load
- 60fps@200 同屏弹幕（中端 Android 目标）

**SDK 不做的事：** 网络 / 输入框 / 屏蔽词 / 持久化设置——全留给业务层。

完整 demo 见 [`example/lib/m11_danmaku_demo_page.dart`](example/lib/m11_danmaku_demo_page.dart)。

## 监听后端选择

```dart
controller.events.listen((event) {
  switch (event) {
    case BackendSelected(:final kind, :final fromMemory):
      print('Active backend: $kind (fromMemory=$fromMemory)');
    case FallbackTriggered(:final reason, :final errorCategory):
      print('Fell back to IJK: $reason / $errorCategory');
  }
});
```

## 用 value 驱动 UI

```dart
ValueListenableBuilder<NiumaPlayerValue>(
  valueListenable: controller,
  builder: (_, value, __) {
    if (value.hasError) return ErrorView(value.error!);
    if (!value.initialized) return const CircularProgressIndicator();
    return NiumaPlayerView(controller);
  },
);
```

播放 / 暂停图标用 `value.effectivelyPlaying` —— 它在 `buffering` 期间仍为 `true`，所以图标不会在播放中途闪烁。

## 读取 / 清除设备记忆

```dart
// 清除"该设备需要走 IJK"的记忆。在"重置缓存"流程里调用。
await NiumaPlayerController.clearDeviceMemory();
```

## 架构

```
NiumaPlayerController  (Dart, single public façade)
    │
    ├── iOS / Web → VideoPlayerBackend → package:video_player
    │
    └── Android   → NativeBackend → niuma_player Kotlin plugin
                                     │
                                     ├── ExoPlayerSession  (default fast path)
                                     └── IjkSession        (rescue path)
                                       ↑
                          Native owns DeviceMemoryStore — Dart side just
                          retries with `forceIjk: true` on first failure.
```

完整设计参见 [`doc/plans/2026-04-24-niuma-player-design.md`](doc/plans/2026-04-24-niuma-player-design.md)。

## 示例 app

`example/` 目录提供了端到端的演示，覆盖七种场景 —— happy path、强制 IJK、循环、错误路径等。运行方式：

```bash
cd example
flutter run -d <device>
```

## 测试

```bash
flutter test
```

Dart 侧状态机在 `test/state_machine_test.dart` 中达到 100% 分支覆盖（iOS / Web / Android happy path / Android retry-success / Android retry-fails / wall-clock 超时）。Kotlin 侧通过示例 app 的诊断页验证。

## FAQ

**Q: iOS 上能免费拿到 IJK 回退吗？**
不行 —— iOS 完全使用 AVPlayer。AVPlayer 能处理 iOS 能解的所有编码，没必要在那里塞一份 FFmpeg。回退方案仅限 Android。

**Q: 为什么 HLS 在 Chrome / Firefox 里播不了？**
这些浏览器原生不支持 HLS，只有 Safari 支持。如果你需要广泛覆盖浏览器的 HLS，请引入 [`video_player_web_hls`](https://pub.dev/packages/video_player_web_hls) —— 它会自动注册并通过 hls.js 处理 m3u8。我们没有默认打包它，因为 hls.js 会让 web bundle 增大约 250KB。

**Q: 测试时能不能在指定设备上强制走 IJK？**
可以 —— 给 controller 传 `NiumaPlayerOptions(forceIjkOnAndroid: true)` 即可。

**Q: 设备记忆能跨 app 重装保留吗？**
不能，它存在 `SharedPreferences`，卸载会被清掉。这是有意为之 —— 全新安装应该重新探测。

## 路线图

- **M4** —— 可选磁盘缓存层（重放命中缓存；Android 走 `SimpleCache`，iOS 走 AVAssetResourceLoader）
- **M5** —— 短视频 reels 用的预加载池（N 个并行预热的 controller + LRU）
- **M7** ✅ —— 编排层（multi-line + `switchLine`、source middleware、续播位置、retry policy、广告调度、analytics）
- **M8** ✅ —— 缩略图 VTT scrub preview（sprite 解析 + ImageProvider 暴露）
- **M9** ✅ —— UI overlay：`NiumaPlayer` 一体化组件 + `NiumaPlayerTheme` + 9 个原子控件 + `NiumaFullscreenPage` + `NiumaAdOverlay` + `NiumaScrubPreview`
- **Backlog** —— 字幕 track 选择（WebVTT 多语言字幕 + sidecar / HLS 内嵌都支持）
- 内置 `video_player_web_hls` opt-in 开关

## 贡献

参见 [CONTRIBUTING.md](CONTRIBUTING.md)。欢迎 PR —— 提交前请先跑 `flutter analyze && flutter test`。

## 许可证

Apache-2.0。参见 [LICENSE](LICENSE)。
