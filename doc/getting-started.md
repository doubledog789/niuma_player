# Getting Started

把 niuma_player（headless 视频播放内核）接入到自家 Flutter app。

> niuma_player 不提供播放器控件皮肤。你用无样式渲染面 `NiumaPlayerView`
> 渲染画面、监听 `controller.value` 自己拼控件。需要现成的复杂控件参考实现，
> 看 git 历史里的 niuma_ui 参考皮，或让 AI 按你的 design token 生成。

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

`ios/Runner/Info.plist`：

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

PiP 不需要额外原生代码——核内部反射 `video_player_avfoundation` 拿 AVPlayer 接
`AVPictureInPictureController`。

### 2.2 Android

`android/app/src/main/AndroidManifest.xml`：

```xml
<uses-permission android:name="android.permission.INTERNET"/>

<application
    android:usesCleartextTraffic="true">                 <!-- 允许 HTTP 视频源 -->
    <activity
        android:name=".MainActivity"
        android:supportsPictureInPicture="true"          <!-- PiP 必需 -->
        android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode">
        ...
    </activity>
</application>
```

`MainActivity.kt`——必须接 PiP 回调，否则核收不到进/退 PiP 事件：

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

### 2.3 Web

`web/index.html` `<head>` 内：

```html
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
<meta name="theme-color" content="#000000">
```

HLS：mp4 在所有浏览器原生可播，m3u8 在 Safari 原生可播。Chrome / Firefox /
Edge 的 HLS 走核内置 vendored `hls.js`，仅在播放 HLS 源时运行时懒注入，无需额外
配置。Web 端基于 `package:web`，可随 `flutter build web --wasm` 编译。

---

## 3. Hello World

`NiumaPlayerView` 渲染画面，`ValueListenableBuilder<NiumaPlayerValue>` 监听状态
自己拼控件。

```dart
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});
  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
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
    return Scaffold(
      body: Column(
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: NiumaPlayerView(_c)),
          ValueListenableBuilder<NiumaPlayerValue>(
            valueListenable: _c,
            builder: (context, value, _) {
              final maxMs = value.duration.inMilliseconds;
              return Row(
                children: [
                  IconButton(
                    icon: Icon(
                        value.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: value.isPlaying ? _c.pause : _c.play,
                  ),
                  Expanded(
                    child: Slider(
                      value: value.position.inMilliseconds
                          .clamp(0, maxMs)
                          .toDouble(),
                      max: maxMs > 0 ? maxMs.toDouble() : 1,
                      onChanged: maxMs > 0
                          ? (v) => _c
                              .seekTo(Duration(milliseconds: v.round()))
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
      ),
    );
  }
}
```

可运行版本见 [`example/lib/minimal_player/minimal_player.dart`](../example/lib/minimal_player/minimal_player.dart)。

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
        source: NiumaDataSource.network('https://cdn1/video.m3u8'),
      ),
      MediaLine(
        id: 'backup',
        label: '备线路',
        priority: 1,
        source: NiumaDataSource.network('https://cdn2/video.m3u8'),
      ),
    ],
    defaultLineId: 'main',
  ),
  // 默认两条 policy 都开着，列出来给你看
  options: const NiumaPlayerOptions(
    autoFailoverOnInitialError: true,   // 主线路 init 失败 → 自动尝试 backup
    rollbackOnSwitchFailure: true,      // 用户主动切换失败 → 回滚原线路
  ),
)..initialize();
```

业务侧主动切换：
```dart
await controller.switchLine('backup');
```

切换失败（且 `rollbackOnSwitchFailure: true`）时 controller 静默回滚，`await`
不抛错。监听事件流拿失败信号：
```dart
controller.events.listen((e) {
  if (e is LineSwitchFailed) {
    print('切换到 ${e.toId} 失败：${e.error}（已自动回滚）');
  }
});
```

---

## 5. 自己拼控件 / 让 AI 生成

所有播放控件都由 `controller.value` 驱动，你自己写：

- 播放 / 暂停：`value.isPlaying ? controller.pause() : controller.play()`
- 进度条：`value.position` / `value.duration` / `controller.seekTo(...)`
- 倍速：`controller.setPlaybackSpeed(1.5)`
- 音量：`controller.setVolume(0.8)`
- 缓冲：`value.bufferedPosition`
- loading / error / ended 三态：看 `value.phase`（`opening` / `buffering` /
  `error` → `value.error` / `ended`）

复杂控件（bili 风长视频壳、抖音风短视频、弹幕 overlay、投屏面板、缩略图预
览）有成熟参考实现保留在 **git 历史**的 niuma_ui 参考皮里：

```bash
git log --all -- 'example/lib/niuma_ui/**'           # 定位 commit
git show <sha>:example/lib/niuma_ui/core/niuma_player.dart   # 取文件
```

或者把 `controller.value` 字段表 + 你的 design token 喂给 AI，让它按需生成。

---

## 下一步

- 完整公开符号速查：[`doc/api-reference.md`](api-reference.md)
- 最小 demo 源码：[`example/lib/minimal_player/minimal_player.dart`](../example/lib/minimal_player/minimal_player.dart)
- 版本变更：[`CHANGELOG.md`](../CHANGELOG.md)
