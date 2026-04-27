# niuma_player

[![CI](https://github.com/niuma/niuma_player/actions/workflows/ci.yml/badge.svg)](https://github.com/niuma/niuma_player/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/flutter-%E2%89%A53.10-blue)](https://flutter.dev)

Production-grade Flutter video player with a unified `controller.value` API across iOS, Android, and Web — and an automatic ExoPlayer → IJK fallback path on Android so older / Huawei devices that can't hardware-decode still play.

## Why

`package:video_player` is the obvious starting point, but on Android it has two well-known failure modes that bite enterprise apps:

1. **Hardware decoder gaps on older / Huawei devices** — black screen, no error, no playback.
2. **HLS in restrictive networks** — ExoPlayer's HLS impl can stall on certain CDNs, and the only practical rescue is an FFmpeg-based player like IJK.

`niuma_player` fixes both transparently. On Android the native plugin tries ExoPlayer first; if it fails before the first frame, it switches to IJK, **remembers** the device fingerprint in persistent storage (`SharedPreferences`), and goes straight to IJK on every subsequent launch — no more "the app worked yesterday" mystery.

iOS uses AVFoundation through `package:video_player`. Web uses the browser's `<video>` element through `package:video_player`. **Same Dart API on all three.**

## Features

- **One controller, three platforms** — `NiumaPlayerController` exposes the same `value`, events, and command surface everywhere.
- **Phase-exclusive state machine** — `playing`, `paused`, `buffering`, `ended`, `error` are mutually exclusive; no more reconciling `isBuffering && !isPlaying && !isCompleted` flicker.
- **Structured errors** — `PlayerErrorCategory` (`transient` / `codecUnsupported` / `network` / `terminal` / `unknown`) instead of regex-matching error strings.
- **Try-Fail-Remember on Android** — automatic ExoPlayer → IJK fallback, persistent per-device, with a public `clearDeviceMemory()` for "reset cache" UI flows.
- **Loop without flicker** — native side restarts on completion without exposing `phase=ended`, so `setLooping(true)` videos stay visually continuous.
- **Drop-in widget** — `NiumaPlayerView(controller)` picks the right rendering primitive (`VideoPlayer` / `Texture`) for the active backend.
- **Fully testable** — dependency-injected `BackendFactory` + `PlatformBridge` let the state machine run in pure Dart unit tests, no platform channels needed.

## Platform support

| Platform | Backend | HLS support |
|---|---|---|
| iOS | AVPlayer (via `video_player`) | Native (AVFoundation) |
| Android | ExoPlayer ↔ IJK (own native plugin) | Native (HLS via media3-exoplayer-hls; IJK via FFmpeg) |
| Web (Safari) | `<video>` (via `video_player`) | Native |
| Web (Chrome / Firefox / Edge) | `<video>` (via `video_player`) | **Not built-in** — add `video_player_web_hls` if needed |

## Install

```yaml
dependencies:
  niuma_player:
    git:
      url: https://github.com/niuma/niuma_player.git
      ref: main
```

> When published on pub.dev, replace with `niuma_player: ^0.1.0`.

## 5-line quick start

```dart
final controller = NiumaPlayerController(
  NiumaDataSource.network('https://example.com/big_buck_bunny.mp4'),
);
await controller.initialize();
controller.play();
// In your widget tree:
NiumaPlayerView(controller);
```

That's the whole API for the happy path. The Try-Fail-Remember mechanism, error categorization, and backend selection events are all opt-in extras you don't need to touch.

## Listening to backend selection

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

## Driving UI from the value

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

Use `value.effectivelyPlaying` for the play / pause icon — it stays `true` during `buffering`, so the icon doesn't flicker mid-playback.

## Reading / clearing device memory

```dart
// Wipe the "this device needs IJK" memory. Call from "reset cache" flows.
await NiumaPlayerController.clearDeviceMemory();
```

## Architecture

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

See [`doc/plans/2026-04-24-niuma-player-design.md`](doc/plans/2026-04-24-niuma-player-design.md) for the full design.

## Example app

The `example/` directory has an end-to-end demo with seven scenarios — happy path, force-IJK, looping, error path, etc. Run it with:

```bash
cd example
flutter run -d <device>
```

## Testing

```bash
flutter test
```

The Dart-side state machine has 100% branch coverage in `test/state_machine_test.dart` (iOS / Web / Android happy path / Android retry-success / Android retry-fails / wall-clock timeout). The Kotlin side is verified through the example app's diagnostics page.

## FAQ

**Q: Will I get the IJK fallback for free on iOS?**
No — iOS uses AVPlayer exclusively. AVPlayer handles every codec iOS can decode, and we have no need to ship FFmpeg there. The fallback story is Android-only.

**Q: Why doesn't HLS play in Chrome / Firefox?**
Those browsers don't natively support HLS. Safari does. If you need broad-browser HLS, add [`video_player_web_hls`](https://pub.dev/packages/video_player_web_hls) — it'll auto-register and handle m3u8 sources via hls.js. We don't bundle it by default because hls.js adds ~250KB to the web bundle.

**Q: Can I force IJK on a specific device for testing?**
Yes — pass `NiumaPlayerOptions(forceIjkOnAndroid: true)` to the controller.

**Q: Does the device memory persist across app reinstalls?**
No, it's in `SharedPreferences`, which is wiped on uninstall. This is intentional — a fresh install should re-probe.

## Roadmap

- **M4** — Optional disk cache layer (replays hit cache; Android via `SimpleCache`, iOS via AVAssetResourceLoader)
- **M5** — Preload pool for short-video reels (N parallel pre-warmed controllers + LRU)
- Built-in `video_player_web_hls` opt-in flag
- Picture-in-picture support
- Subtitle track selection

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). PRs welcome — please run `flutter analyze && flutter test` before submitting.

## License

Apache-2.0. See [LICENSE](LICENSE).
