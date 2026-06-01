# 贡献指南 niuma_player

感谢你的关注！本文档涵盖实操要点。

## 基本规则

- **非小改动请先开 issue 讨论。** 5 行讨论能省下 500 行 PR 重写的成本。
- 友善对待他人。遵守开源社区通行的礼节。

## 开发环境搭建

```bash
git clone https://github.com/niuma/niuma_player.git
cd niuma_player
flutter pub get
flutter analyze
flutter test
```

运行示例 app：

```bash
cd example
flutter run -d <device>
```

## 项目结构

`niuma_player` 是 **headless 视频播放内核**——包内零 UI widget（除无样式渲染面
`NiumaPlayerView`）。曾经的整套 UI 参考皮（niuma_ui）保留在 git 历史。

```
lib/                       公开 Dart API（barrel：lib/niuma_player.dart）
├── src/domain/            纯接口 + 状态值对象（PlayerBackend / player_state / 手势值对象…）
├── src/data/              三平台后端 + 平台桥（VideoPlayerBackend / NativeBackend / web…）
├── src/orchestration/     纯 Dart 编排（multi_source / auto_failover / retry / middleware）
├── src/cast/              投屏值类型（CastDevice / CastSession / CastState）
└── src/player/            controller + NiumaPlayerView + 手势/全屏 headless controller
android/src/main/kotlin/   Android 原生插件（ExoPlayer ↔ IJK，IJK 已升 FFmpeg 7.1.1）
ios/                       iOS pod（基于 video_player AVPlayer）+ PiP 反射桥
test/                      纯 Dart 单元测试
example/                   100 行最小 demo（消费内核）
```

## 提 PR 之前

1. `flutter analyze` —— 必须无警告
2. `flutter test` —— 必须全绿
3. `flutter build web`，并跑至少一个 `flutter build apk --debug` / `flutter build ios --no-codesign`（取决于你改了哪部分）
4. 在 `CHANGELOG.md` 的 `## [Unreleased]` 下补充条目
5. 改了公开 API：升级版本号 + 在 changelog 里加 `BREAKING CHANGE:` 说明

## 编码规范

- 遵循 `analysis_options.yaml`（用的是 `flutter_lints` 严格档）。
- 公开的 Dart 符号**必须**写 `///` 文档注释。
- 一个文件一个职责。辅助 extension 方法放进 `_ext.dart`。
- 测试文件就近放在它所验证的层旁边（`test/state_machine_test.dart` 等）。

## 提交信息约定

我们使用 Conventional Commits：

```
feat: add disk cache for replays
fix(android): handle null surface on detach
docs: clarify HLS-on-web caveat in README
```

## 报告 bug

请使用 `.github/ISSUE_TEMPLATE/` 下的 issue 模板。务必附上：

- 平台 + 操作系统版本
- 设备型号（Android 用 `adb shell getprop ro.product.model`）
- 一个失败的测试 / 最小复现样例
- 堆栈 + `BackendSelected` / `FallbackTriggered` 事件日志

## 许可证

提交贡献即表示你同意以 Apache-2.0 协议授权该贡献。
