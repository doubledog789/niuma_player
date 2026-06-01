# niuma_player_example

niuma_player（headless 视频播放内核）的**最小用法 demo**。

`lib/main.dart` 约 100 行，演示接入 headless 核的最小闭环：

- `NiumaPlayerController.dataSource(NiumaDataSource.network(url))..initialize()` 驱动播放
- `AspectRatio(16/9, child: NiumaPlayerView(c))` 渲染画面
- `ValueListenableBuilder<NiumaPlayerValue>` 监听状态，自己拼播放/暂停按钮 +
  进度 Slider + 时间 label

niuma_player **不含任何 UI widget**——控件都由接入方监听 `controller.value` 自
己写。复杂控件（长视频壳 / 短视频 / 弹幕 overlay / 投屏面板 / 缩略图预览）的参考
实现保留在 git 历史的 niuma_ui 参考皮里，需要时 `git log` / `git show` 捞，或让
AI 按需生成。

## 运行

```bash
flutter run -d <device-id>
```
