---
name: Bug report
about: Something doesn't work as expected
title: '[bug] '
labels: bug
---

## Summary

<!-- One-line description of the problem. -->

## Environment

- niuma_player version:
- Flutter version (`flutter --version`):
- Platform: <!-- iOS / Android / Web -->
- OS version:
- Device model: <!-- Android: `adb shell getprop ro.product.model` -->

## Reproduction

<!-- Smallest piece of code or steps that triggers the bug. -->

```dart
final controller = NiumaPlayerController(
  NiumaDataSource.network('https://...'),
);
await controller.initialize();
```

## Expected vs. actual

- **Expected**:
- **Actual**:

## Logs

<!-- Paste BackendSelected / FallbackTriggered events from controller.events,
     and any stack trace. -->

```
[niuma_player] ...
```
