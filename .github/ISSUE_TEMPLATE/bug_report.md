---
name: Bug 报告
about: 出现了不符合预期的行为
title: '[bug] '
labels: bug
---

## 概述

<!-- 用一行话描述问题。 -->

## 环境

- niuma_player 版本：
- Flutter 版本（`flutter --version`）：
- 平台：<!-- iOS / Android / Web -->
- 操作系统版本：
- 设备型号：<!-- Android: `adb shell getprop ro.product.model` -->

## 复现步骤

<!-- 触发该 bug 的最小代码片段或步骤。 -->

```dart
final controller = NiumaPlayerController(
  NiumaDataSource.network('https://...'),
);
await controller.initialize();
```

## 预期行为 vs 实际行为

- **预期**：
- **实际**：

## 日志

<!-- 贴出 controller.events 中的 BackendSelected / FallbackTriggered 事件，
     以及任何堆栈信息。 -->

```
[niuma_player] ...
```
