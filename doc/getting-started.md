# Getting Started

5 分钟把 niuma_player 接入到自家 Flutter app。

---

## 1. 添加依赖

`pubspec.yaml`：
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

---

## 2. 平台原生配置

### 2.1 iOS

**`ios/Runner/Info.plist`**：

```xml
<!-- 允许 HTTP 视频源（HTTPS 不需要这一段） -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>

<!-- 想要 PiP 后台音频继续播 -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

PiP 不需要额外原生代码——SDK 内部反射 `video_player_avfoundation` 拿 AVPlayer 接 `AVPictureInPictureController`。

### 2.2 Android

**`android/app/src/main/AndroidManifest.xml`**：

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>

<application
    android:usesCleartextTraffic="true">                 <!-- 允许 HTTP 视频源 -->
    <activity
        android:name=".MainActivity"
        android:exported="true"
        android:launchMode="singleTop"
        android:taskAffinity=""                          <!-- PiP 推荐 -->
        android:supportsPictureInPicture="true"          <!-- PiP 必需 -->
        android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
        android:hardwareAccelerated="true"
        android:windowSoftInputMode="adjustResize">
        ...
    </activity>
</application>
```

**`android/app/src/main/kotlin/.../MainActivity.kt`**——必须接 PiP 回调：

```kotlin
package com.your.package

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

> 不接这一行，PiP 退出时 SDK 收不到事件，控件层会一直被藏。SDK v0.9.1 加了 lifecycle resume 兜底但仍建议正确接入。

### 2.3 Web

**`web/index.html`** `<head>` 内：

```html
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
<meta name="theme-color" content="#000000">
```

`viewport-fit=cover` 让 PWA 全屏可以覆盖到 iPhone notch / home indicator 区域（SDK 用 SafeArea 主动补 inset）。

如果 Chrome / Firefox 需要 HLS：在 `pubspec.yaml` 加 `video_player_web_hls`（SDK 不内置）。

---

## 3. Hello World

```dart
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});
  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final NiumaPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NiumaPlayerController.dataSource(
      NiumaDataSource.network('https://example.com/video.mp4'),
    );
    _controller.initialize().then((_) => _controller.play());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: NiumaPlayer(controller: _controller),
        ),
      ),
    );
  }
}
```

---

## 4. 多线路 + 失败回滚

```dart
final controller = NiumaPlayerController(
  NiumaMediaSource.lines(
    lines: [
      MediaLine(
        id: 'main',
        label: '主线路',
        priority: 0,
        source: NiumaDataSource.network('https://cdn1.../video.m3u8'),
      ),
      MediaLine(
        id: 'backup',
        label: '备线路',
        priority: 1,
        source: NiumaDataSource.network('https://cdn2.../video.m3u8'),
      ),
    ],
    defaultLineId: 'main',
  ),
  // 默认两条 policy 都开着，列出来给你看
  options: const NiumaPlayerOptions(
    autoFailoverOnInitialError: true,   // 主线路 init 失败 → 自动尝试 backup
    rollbackOnSwitchFailure: true,      // 用户主动切换失败 → 回滚原线路
  ),
);
```

业务侧主动切换：
```dart
await controller.switchLine('backup');
```

如果切换失败（且 `rollbackOnSwitchFailure: true`），controller 会静默回滚，`await` 不抛错。监听事件流可以拿到失败信号：
```dart
controller.events.listen((e) {
  if (e is LineSwitchFailed) {
    print('切换到 ${e.toId} 失败：${e.error}（已自动回滚）');
  }
});
```

---

## 5. 短视频 PageView

```dart
class FeedPage extends StatefulWidget {
  // ...
}

class _FeedPageState extends State<FeedPage> {
  final PageController _pageController = PageController();
  final List<NiumaPlayerController> _controllers = [];
  int _currentIndex = 0;

  void _initController(String url) {
    final c = NiumaPlayerController.dataSource(NiumaDataSource.network(url));
    c.initialize();
    _controllers.add(c);
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      onPageChanged: (i) => setState(() => _currentIndex = i),
      itemCount: _controllers.length,
      itemBuilder: (ctx, i) => NiumaShortVideoPlayer(
        controller: _controllers[i],
        isActive: i == _currentIndex,    // PageView 协调：只播当前页
        loop: true,
        leftCenterBuilder: (c, ctl) =>
            NiumaShortVideoFullscreenButton(controller: ctl),
      ),
    );
  }
}
```

完整短视频 demo：[`example/lib/short_video_demo_page.dart`](../example/lib/short_video_demo_page.dart)

---

## 6. 集成弹幕

```dart
final danmaku = NiumaDanmakuController()
  ..addAll([
    DanmakuItem(
      position: const Duration(seconds: 5),
      text: 'awsl 这画面太顶了',
      color: Colors.white,
    ),
    // ... 业务从 API 拉的弹幕
  ]);

NiumaPlayer(
  controller: controller,
  danmakuController: danmaku,
  onDanmakuInputTap: () async {
    // 业务自家弹幕输入 UI
    final text = await showMyDanmakuInput(context);
    if (text != null) {
      danmaku.add(DanmakuItem(
        position: controller.value.position,
        text: text,
      ));
    }
  },
)
```

完整弹幕 demo：[`example/lib/danmaku_demo.dart`](../example/lib/danmaku_demo.dart)

---

## 7. 自定义 UI

### 7.1 控件条配置

SDK 自带 3 个 preset：

```dart
fullscreenControlBarConfig: NiumaControlBarConfig.minimal,  // 最简
fullscreenControlBarConfig: NiumaControlBarConfig.bili,     // bili 风（默认）
fullscreenControlBarConfig: NiumaControlBarConfig.full,     // 全开（含 cast/PiP/lineSwitch/more）
```

或自家配：

```dart
fullscreenControlBarConfig: const NiumaControlBarConfig(
  topLeading: [NiumaControlButton.back, NiumaControlButton.title],
  topActions: [NiumaControlButton.more],
  bottomLeft: [
    NiumaControlButton.playPause,
    NiumaControlButton.danmakuToggle,
    NiumaControlButton.danmakuInput,
  ],
  bottomRight: [
    NiumaControlButton.speed,
    NiumaControlButton.lineSwitch,
  ],
  centerPlayPause: true,
  showProgressBar: true,
)
```

### 7.2 按钮级 override

把某个 enum 槽换成自家完全自定义 widget：

```dart
buttonOverrides: {
  NiumaControlButton.speed: ButtonOverride.builder((ctx) {
    return TextButton(
      onPressed: () => showMySpeedSheet(ctx),
      child: const Text('🚀 极速'),
    );
  }),
}
```

或保留 SDK 框架但换 icon / label / onTap：

```dart
buttonOverrides: {
  NiumaControlButton.cast: ButtonOverride.fields(
    icon: const Icon(Icons.tv),
    label: '投到电视',
    onTap: () => showMyCastSheet(),
  ),
}
```

### 7.3 反馈 UI

```dart
NiumaPlayer(
  controller: controller,
  loadingBuilder: (ctx) => MyLoadingWidget(),
  errorBuilder: (ctx, err) => MyErrorWidget(err.message, onRetry: ...),
  endedBuilder: (ctx) => MyEndedWidget(onReplay: ...),
)
```

完整自定义 UI demo：[`example/lib/custom_controls_demo.dart`](../example/lib/custom_controls_demo.dart) + [`custom_feedback_ui_demo.dart`](../example/lib/custom_feedback_ui_demo.dart)

---

## 下一步

- 完整 API 参考：[`doc/api-reference.md`](api-reference.md)
- 各 demo 源码：[`example/lib/`](../example/lib/)
- 上一版变更：[`CHANGELOG.md`](../CHANGELOG.md)
