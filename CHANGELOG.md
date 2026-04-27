# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-27

First public release.

### Added
- `NiumaPlayerController` — unified Dart-side controller for iOS, Web, and Android.
- `NiumaPlayerView` — drop-in widget that picks the right rendering primitive
  for the active backend.
- `NiumaPlayerValue` snapshot with phase-exclusive state machine
  (`idle / opening / ready / playing / paused / buffering / ended / error`).
- Structured error model: `PlayerError` + `PlayerErrorCategory`
  (`transient / codecUnsupported / network / terminal / unknown`).
- Backend selection events: `BackendSelected`, `FallbackTriggered`.
- iOS / Web routing through `package:video_player` (AVPlayer / `<video>`).
- Android native plugin with two backends:
  - `ExoPlayerSession` — default hardware-accelerated path
    (androidx.media3 1.4.1, including HLS).
  - `IjkSession` — FFmpeg-based rescue path for devices without working
    hardware decoders.
- Try-Fail-Remember on Android: native side persistently marks devices
  that can't run ExoPlayer in `DeviceMemoryStore` (SharedPreferences) and
  goes straight to IJK on subsequent launches. Dart side does a single
  retry with `forceIjk: true` on first-attempt failure.
- `NiumaPlayerController.clearDeviceMemory()` for "reset cache" UI flows.
- Loop without `phase=ended` flicker — native restarts on completion
  while staying in `playing`.
- Dependency-injected `BackendFactory` + `PlatformBridge` for pure-Dart
  state-machine tests (no platform channels).
- 14 unit tests covering iOS / Web / Android happy path, retry success,
  retry failure, wall-clock timeout, plus `DeviceMemory` persistence.

[Unreleased]: https://github.com/niuma/niuma_player/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/niuma/niuma_player/releases/tag/v0.1.0
