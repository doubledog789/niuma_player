# Contributing to niuma_player

Thanks for your interest! This doc covers the practical bits.

## Ground rules

- **Open an issue first for non-trivial changes.** A 5-line discussion saves a 500-line PR rewrite.
- Be kind. Standard open-source etiquette applies.

## Development setup

```bash
git clone https://github.com/niuma/niuma_player.git
cd niuma_player
flutter pub get
flutter analyze
flutter test
```

To run the example app:

```bash
cd example
flutter run -d <device>
```

## Project layout

```
lib/                       Public Dart API (NiumaPlayerController, etc.)
├── src/domain/            Pure interfaces (PlayerBackend, BackendFactory…)
├── src/data/              Concrete backends (VideoPlayerBackend, NativeBackend)
└── src/presentation/      Widgets & controller
android/src/main/kotlin/   Android native plugin (ExoPlayer + IJK)
ios/                       iOS pod (uses video_player AVPlayer)
test/                      Pure-Dart unit tests
example/                   Demo app exercising every code path
doc/plans/                 Design docs and milestone plans
```

## Before opening a PR

1. `flutter analyze` — must be clean
2. `flutter test` — must be green
3. `flutter build web` and at least one of `flutter build apk --debug` / `flutter build ios --no-codesign` (depending on what you touched)
4. Update `CHANGELOG.md` under `## [Unreleased]`
5. Public API changes: bump version + add a `BREAKING CHANGE:` note in the changelog

## Coding style

- Follow `analysis_options.yaml` (it's `flutter_lints` strict).
- Public Dart symbols **must** have a `///` doc comment.
- One responsibility per file. Helper extension methods go in `_ext.dart`.
- Tests live next to the layer they verify (`test/state_machine_test.dart`, etc.).

## Commit message convention

We use Conventional Commits:

```
feat: add disk cache for replays
fix(android): handle null surface on detach
docs: clarify HLS-on-web caveat in README
```

## Reporting bugs

Use the issue templates in `.github/ISSUE_TEMPLATE/`. Always include:

- Platform + OS version
- Device model (Android: `adb shell getprop ro.product.model`)
- A failing test / minimal reproduction
- Stack trace + `BackendSelected` / `FallbackTriggered` event log

## License

By contributing, you agree your contributions are licensed under Apache-2.0.
