# niuma_player_example

niuma_player（headless 视频播放内核）的接入示例。

入口在 `lib/main.dart`，包含三种场景：

- `minimal_player/`：最小接入，只有 `NiumaPlayerController`、`NiumaPlayerView`
  和一组基础播放控件。
- `standard_player/`：完整参考播放器皮，演示顶栏、底栏、手势、错误/结束态和全屏。
- `feed_demo/`：短视频/短剧列表，演示 `NiumaPlayerPool` 的 acquire / release
  生命周期；非 Android 平台额外演示 preload，Android 上保守保持单 native
  decoder，避免 MediaCodec buffer 压力。

SDK 不提供播放器控件皮肤，只提供无样式视频渲染面 `NiumaPlayerView` 和 headless
controller。业务控件监听 `controller.value` 自己拼。

## 运行

```bash
flutter run -d <device-id>
```
