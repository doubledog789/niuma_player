# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.4] - 2026-05-25

### Fixed

- Vendored the custom-compiled `ijkplayer` `.aar` (13 MB) into git and the
  published package. It was previously git-ignored and fetched by a download
  script whose release URL no longer exists, so neither git nor pub.dev
  consumers received the binary and every Android build failed to resolve
  `tv.danmaku.ijk:ijkplayer`. The aar now ships under `android/localmaven/`,
  so Android builds work out of the box. Removed the dead download script.

## [0.0.3] - 2026-05-09

### Fixed

- Bumped `video_player` lower bound to `>=2.10.0`. The 2.8.0 lower bound
  failed pana downgrade analysis because `VideoPlayerController.playerId`
  (used by the iOS PiP bridge to map a Flutter texture id to its native
  AVPlayer instance) was only added in `video_player 2.10.0`.
- Declared web platform support in `pubspec.yaml` plugin manifest with a
  no-op `NiumaPlayerWebRegistrar` stub. Web behavior is implemented in pure
  Dart via conditional imports (`WebVideoBackend`); the stub exists only so
  Flutter's web plugin discovery can satisfy the platform declaration.
- Trimmed `CHANGELOG.md` to public 0.0.x entries only. The full
  internal-preview history (0.1.0 through 0.9.1) — which is mostly Chinese
  prose and was tripping pub.dev's non-ASCII content check — moved to
  [`doc/CHANGELOG_zh_internal_preview.md`](doc/CHANGELOG_zh_internal_preview.md).

## [0.0.2] - 2026-05-09

### Fixed

- Replaced `dart:js_util` (removed in Dart SDK 3.11) with `dart:js_interop` /
  `dart:js_interop_unsafe` in `web_video_backend.dart`. Fixes pub.dev pana
  static analysis failure that previously zeroed out platform support score.
- Shortened pubspec.yaml description to fit pub.dev 60-180 char limit.
- Added English-language summaries to `CHANGELOG.md`.

## [0.0.1] - 2026-05-09

**First public pub.dev release.** Version reset from internal-preview 0.9.x
to 0.0.1 as the inaugural public SDK version. Feature set equivalent to
internal 0.9.1, including:

- 3-tier backend abstraction (VideoPlayerBackend for iOS/Web, NativeBackend
  for Android) plus Android Try-Fail-Remember device memory.
- Orchestration layer (multi-line, retry policy, source middleware, resume
  position, WebVTT thumbnails, danmaku bucket loader, auto-failover).
- All-in-one `NiumaPlayer` widget plus 22 atomic control widgets and a
  configurable `NiumaControlBar`.
- Picture-in-Picture (iOS via reflection bridge, Android native).
- Cast: DLNA and AirPlay auto-registration via `NiumaCastRegistry`.
- Feedback UI builder slots: `loadingBuilder`, `errorBuilder`, `endedBuilder`.
- Short-video player with TikTok-style gestures, scrubber, speed control.
- Web fullscreen, cross-backend swap coordination, iOS Safari quirk fixes.

For the detailed history of internal-preview iterations leading up to this
release (0.1.x through 0.9.1), see
[`doc/CHANGELOG_zh_internal_preview.md`](doc/CHANGELOG_zh_internal_preview.md)
(Chinese).
