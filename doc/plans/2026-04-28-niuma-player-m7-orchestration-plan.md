# M7 Orchestration Layer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart orchestration layer (`lib/src/orchestration/` + `lib/src/observability/` + initial `lib/src/testing/` doubles) and wire its kernel touchpoints (multi-source switch + middleware + retry on `NiumaPlayerController`).

**Architecture:** Add five orchestration units (multi-source, resume, retry, ads, source middleware) plus an analytics event hook. Each unit is a value class (data) + an orchestrator (behaviour). The kernel `NiumaPlayerController` gains a `NiumaMediaSource` first arg, optional `middlewares:` and `retryPolicy:` params, and a `switchLine(id)` method. Everything orchestration-side is pure Dart and unit-testable without platform channels.

**Tech Stack:** Dart, `flutter_test`, `fake_async`, `shared_preferences` (already in pubspec via dependency tree — added explicitly here).

**Spec reference:** `doc/plans/2026-04-27-niuma-player-enterprise-dart-design.md` Sections 1, 5, 6, 7.3.

---

## File Structure

### New files

```
lib/src/observability/
├── analytics_event.dart                  AnalyticsEvent sealed class hierarchy
└── analytics_emitter.dart                AnalyticsEmitter typedef

lib/src/orchestration/
├── source_middleware.dart                SourceMiddleware abstract + HeaderInjection + SignedUrl + pipeline runner
├── multi_source.dart                     MediaQuality, MediaLine, NiumaMediaSource, MultiSourcePolicy
├── resume_position.dart                  ResumeStorage, ResumePolicy, ResumeBehaviour, ResumeOrchestrator
├── retry_policy.dart                     RetryPolicy value class
├── ad_schedule.dart                      AdCue, AdController, NiumaAdSchedule, MidRollAd, ad enums
├── ad_scheduler.dart                     AdSchedulerOrchestrator (behaviour)
└── auto_failover.dart                    AutoFailoverOrchestrator (behaviour)

lib/src/testing/
├── fake_resume_storage.dart              In-memory ResumeStorage for tests
└── fake_analytics_emitter.dart           Capturing AnalyticsEmitter for tests

lib/testing.dart                          Public test-double exports

test/orchestration/
├── source_middleware_test.dart
├── multi_source_test.dart
├── resume_position_test.dart
├── retry_policy_test.dart
├── ad_schedule_test.dart
├── ad_scheduler_test.dart
└── auto_failover_test.dart
```

### Modified files

```
lib/src/presentation/niuma_player_controller.dart
   ↳ accept `NiumaMediaSource` + `middlewares` + `retryPolicy`; add `switchLine`
   ↳ emit LineSwitching / LineSwitched / LineSwitchFailed
lib/src/domain/player_state.dart
   ↳ add LineSwitching / LineSwitched / LineSwitchFailed event subclasses
lib/niuma_player.dart
   ↳ export new orchestration / observability surface
test/state_machine_test.dart
   ↳ migrate to NiumaMediaSource.single(NiumaDataSource(...)) form
example/lib/player_page.dart
   ↳ same migration
pubspec.yaml
   ↳ add shared_preferences explicitly
CHANGELOG.md
   ↳ document M7 additions under [Unreleased]
```

---

## Task 1: Analytics event hierarchy

**Files:**
- Create: `lib/src/observability/analytics_event.dart`
- Create: `lib/src/observability/analytics_emitter.dart`
- Test: `test/orchestration/analytics_event_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/orchestration/analytics_event_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/observability/analytics_event.dart';

void main() {
  test('AdImpression equality + hashcode', () {
    final a = AnalyticsEvent.adImpression(
      cueType: AdCueType.preRoll,
      durationShown: const Duration(seconds: 5),
    );
    final b = AnalyticsEvent.adImpression(
      cueType: AdCueType.preRoll,
      durationShown: const Duration(seconds: 5),
    );
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('AdDismissed reasons are distinct', () {
    expect(
      AnalyticsEvent.adDismissed(
        cueType: AdCueType.preRoll,
        reason: AdDismissReason.userSkip,
      ),
      isNot(equals(AnalyticsEvent.adDismissed(
        cueType: AdCueType.preRoll,
        reason: AdDismissReason.timeout,
      ))),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/analytics_event_test.dart`
Expected: FAIL — `analytics_event.dart` does not exist.

- [ ] **Step 3: Implement `AnalyticsEvent`**

```dart
// lib/src/observability/analytics_event.dart
import 'package:flutter/foundation.dart';

enum AdCueType { preRoll, midRoll, pauseAd, postRoll }
enum AdDismissReason { userSkip, timeout, dismissOnTap }

@immutable
sealed class AnalyticsEvent {
  const AnalyticsEvent();

  const factory AnalyticsEvent.adScheduled({
    required AdCueType cueType,
    Duration? at,
  }) = AdScheduled;

  const factory AnalyticsEvent.adImpression({
    required AdCueType cueType,
    required Duration durationShown,
  }) = AdImpression;

  const factory AnalyticsEvent.adClick({
    required AdCueType cueType,
  }) = AdClick;

  const factory AnalyticsEvent.adDismissed({
    required AdCueType cueType,
    required AdDismissReason reason,
  }) = AdDismissed;
}

final class AdScheduled extends AnalyticsEvent {
  const AdScheduled({required this.cueType, this.at});
  final AdCueType cueType;
  final Duration? at;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdScheduled && other.cueType == cueType && other.at == at;

  @override
  int get hashCode => Object.hash(cueType, at);
}

final class AdImpression extends AnalyticsEvent {
  const AdImpression({required this.cueType, required this.durationShown});
  final AdCueType cueType;
  final Duration durationShown;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdImpression &&
          other.cueType == cueType &&
          other.durationShown == durationShown;

  @override
  int get hashCode => Object.hash(cueType, durationShown);
}

final class AdClick extends AnalyticsEvent {
  const AdClick({required this.cueType});
  final AdCueType cueType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AdClick && other.cueType == cueType;

  @override
  int get hashCode => cueType.hashCode;
}

final class AdDismissed extends AnalyticsEvent {
  const AdDismissed({required this.cueType, required this.reason});
  final AdCueType cueType;
  final AdDismissReason reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdDismissed && other.cueType == cueType && other.reason == reason;

  @override
  int get hashCode => Object.hash(cueType, reason);
}
```

```dart
// lib/src/observability/analytics_emitter.dart
import 'analytics_event.dart';

/// User-supplied hook. niuma_player calls this on every internal event;
/// app forwards to its own analytics SDK (Sensors / GIO / Bugly / ...).
typedef AnalyticsEmitter = void Function(AnalyticsEvent event);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/orchestration/analytics_event_test.dart`
Expected: PASS — both tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/src/observability/ test/orchestration/analytics_event_test.dart
git commit -m "feat(observability): add AnalyticsEvent sealed hierarchy + AnalyticsEmitter typedef"
```

---

## Task 2: SourceMiddleware abstract + HeaderInjection

**Files:**
- Create: `lib/src/orchestration/source_middleware.dart`
- Test: `test/orchestration/source_middleware_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/orchestration/source_middleware_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/orchestration/source_middleware.dart';

void main() {
  test('HeaderInjectionMiddleware merges headers into network source', () async {
    const m = HeaderInjectionMiddleware({'Referer': 'https://app.example.com'});
    final input = NiumaDataSource.network('https://cdn/x.mp4',
        headers: {'X-Token': 'abc'});

    final out = await m.apply(input);

    expect(out.uri, 'https://cdn/x.mp4');
    expect(out.headers, {
      'X-Token': 'abc',
      'Referer': 'https://app.example.com',
    });
  });

  test('HeaderInjectionMiddleware ignores non-network sources', () async {
    const m = HeaderInjectionMiddleware({'Referer': 'x'});
    final input = NiumaDataSource.asset('videos/intro.mp4');
    expect(await m.apply(input), same(input));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/source_middleware_test.dart`
Expected: FAIL — `source_middleware.dart` does not exist.

- [ ] **Step 3: Implement abstract + HeaderInjectionMiddleware**

```dart
// lib/src/orchestration/source_middleware.dart
import '../domain/data_source.dart';

/// Transforms a [NiumaDataSource] before it reaches the backend.
/// Run on initialize, on switchLine, and on retry — every reach for
/// the network gets a fresh signed URL / fresh headers.
abstract class SourceMiddleware {
  const SourceMiddleware();
  Future<NiumaDataSource> apply(NiumaDataSource input);
}

class HeaderInjectionMiddleware extends SourceMiddleware {
  const HeaderInjectionMiddleware(this.headers);
  final Map<String, String> headers;

  @override
  Future<NiumaDataSource> apply(NiumaDataSource input) async {
    if (input.type != NiumaSourceType.network) return input;
    return NiumaDataSource.network(
      input.uri,
      headers: {...?input.headers, ...headers},
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/orchestration/source_middleware_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/source_middleware.dart test/orchestration/source_middleware_test.dart
git commit -m "feat(orchestration): SourceMiddleware abstract + HeaderInjectionMiddleware"
```

---

## Task 3: SignedUrlMiddleware

**Files:**
- Modify: `lib/src/orchestration/source_middleware.dart`
- Test: `test/orchestration/source_middleware_test.dart`

- [ ] **Step 1: Add the failing test**

Append to `test/orchestration/source_middleware_test.dart`:

```dart
test('SignedUrlMiddleware swaps URL via signer', () async {
  final m = SignedUrlMiddleware((raw) async => '$raw?sig=ABC');
  final out = await m.apply(NiumaDataSource.network('https://cdn/x.mp4',
      headers: {'X-Token': 'abc'}));

  expect(out.uri, 'https://cdn/x.mp4?sig=ABC');
  expect(out.headers, {'X-Token': 'abc'});
});

test('SignedUrlMiddleware ignores non-network sources', () async {
  var called = false;
  final m = SignedUrlMiddleware((url) async {
    called = true;
    return url;
  });
  await m.apply(NiumaDataSource.file('/tmp/v.mp4'));
  expect(called, isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/source_middleware_test.dart`
Expected: FAIL — `SignedUrlMiddleware` not defined.

- [ ] **Step 3: Implement**

Append to `lib/src/orchestration/source_middleware.dart`:

```dart
class SignedUrlMiddleware extends SourceMiddleware {
  SignedUrlMiddleware(this._signer);
  final Future<String> Function(String rawUrl) _signer;

  @override
  Future<NiumaDataSource> apply(NiumaDataSource input) async {
    if (input.type != NiumaSourceType.network) return input;
    final signedUrl = await _signer(input.uri);
    return NiumaDataSource.network(signedUrl, headers: input.headers);
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/source_middleware_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/source_middleware.dart test/orchestration/source_middleware_test.dart
git commit -m "feat(orchestration): SignedUrlMiddleware"
```

---

## Task 4: Middleware pipeline runner

**Files:**
- Modify: `lib/src/orchestration/source_middleware.dart`
- Test: `test/orchestration/source_middleware_test.dart`

- [ ] **Step 1: Add failing test**

Append:

```dart
test('runMiddlewares applies left-to-right', () async {
  final result = await runSourceMiddlewares(
    NiumaDataSource.network('https://cdn/x.mp4'),
    const [
      HeaderInjectionMiddleware({'A': '1'}),
      HeaderInjectionMiddleware({'B': '2'}),
    ],
  );
  expect(result.headers, {'A': '1', 'B': '2'});
});

test('runMiddlewares with empty list returns input as-is', () async {
  final input = NiumaDataSource.network('https://cdn/x.mp4');
  expect(await runSourceMiddlewares(input, const []), same(input));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/source_middleware_test.dart`
Expected: FAIL — `runSourceMiddlewares` not defined.

- [ ] **Step 3: Implement**

Append to `source_middleware.dart`:

```dart
Future<NiumaDataSource> runSourceMiddlewares(
  NiumaDataSource input,
  List<SourceMiddleware> middlewares,
) async {
  if (middlewares.isEmpty) return input;
  var current = input;
  for (final m in middlewares) {
    current = await m.apply(current);
  }
  return current;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/source_middleware_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/source_middleware.dart test/orchestration/source_middleware_test.dart
git commit -m "feat(orchestration): runSourceMiddlewares pipeline"
```

---

## Task 5: MediaQuality + MediaLine value classes

**Files:**
- Create: `lib/src/orchestration/multi_source.dart`
- Test: `test/orchestration/multi_source_test.dart`

- [ ] **Step 1: Failing test**

```dart
// test/orchestration/multi_source_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/orchestration/multi_source.dart';

void main() {
  test('MediaQuality equality', () {
    expect(
      const MediaQuality(heightPx: 720, bitrate: 1500000),
      equals(const MediaQuality(heightPx: 720, bitrate: 1500000)),
    );
    expect(
      const MediaQuality(heightPx: 720),
      isNot(equals(const MediaQuality(heightPx: 1080))),
    );
  });

  test('MediaLine carries source + label + priority', () {
    final line = MediaLine(
      id: 'cdn-a-720',
      label: '720P',
      source: NiumaDataSource.network('https://cdn-a/720.mp4'),
      quality: const MediaQuality(heightPx: 720),
      priority: 10,
    );
    expect(line.id, 'cdn-a-720');
    expect(line.priority, 10);
    expect(line.source.uri, 'https://cdn-a/720.mp4');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/multi_source_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/src/orchestration/multi_source.dart
import 'package:flutter/foundation.dart';
import '../domain/data_source.dart';

@immutable
class MediaQuality {
  const MediaQuality({this.heightPx, this.bitrate, this.codec});
  final int? heightPx;
  final int? bitrate;
  final String? codec;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaQuality &&
          other.heightPx == heightPx &&
          other.bitrate == bitrate &&
          other.codec == codec;

  @override
  int get hashCode => Object.hash(heightPx, bitrate, codec);
}

@immutable
class MediaLine {
  const MediaLine({
    required this.id,
    required this.label,
    required this.source,
    this.quality,
    this.priority = 0,
  });

  final String id;
  final String label;
  final NiumaDataSource source;
  final MediaQuality? quality;
  final int priority;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/multi_source_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/multi_source.dart test/orchestration/multi_source_test.dart
git commit -m "feat(orchestration): MediaQuality + MediaLine value classes"
```

---

## Task 6: NiumaMediaSource (single + lines factories)

**Files:**
- Modify: `lib/src/orchestration/multi_source.dart`
- Test: `test/orchestration/multi_source_test.dart`

- [ ] **Step 1: Failing tests**

Append:

```dart
test('NiumaMediaSource.single wraps a NiumaDataSource', () {
  final ds = NiumaDataSource.network('https://cdn/x.mp4');
  final src = NiumaMediaSource.single(ds);
  expect(src.lines, hasLength(1));
  expect(src.lines.first.source, same(ds));
  expect(src.lines.first.id, 'default');
  expect(src.defaultLineId, 'default');
});

test('NiumaMediaSource.lines validates defaultLineId is in lines', () {
  expect(
    () => NiumaMediaSource.lines(
      lines: [
        MediaLine(
          id: 'a',
          label: 'A',
          source: NiumaDataSource.network('https://cdn/a'),
        ),
      ],
      defaultLineId: 'b',
    ),
    throwsA(isA<ArgumentError>()),
  );
});

test('NiumaMediaSource.currentLine resolves by id', () {
  final src = NiumaMediaSource.lines(
    lines: [
      MediaLine(
        id: 'a',
        label: 'A',
        source: NiumaDataSource.network('https://cdn/a'),
      ),
      MediaLine(
        id: 'b',
        label: 'B',
        source: NiumaDataSource.network('https://cdn/b'),
      ),
    ],
    defaultLineId: 'b',
  );
  expect(src.currentLine.id, 'b');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/multi_source_test.dart`
Expected: FAIL — `NiumaMediaSource` not defined.

- [ ] **Step 3: Implement**

Append to `multi_source.dart`:

```dart
@immutable
class NiumaMediaSource {
  const NiumaMediaSource._({
    required this.lines,
    required this.defaultLineId,
  });

  factory NiumaMediaSource.single(NiumaDataSource source) {
    return NiumaMediaSource._(
      lines: [
        MediaLine(id: 'default', label: 'default', source: source),
      ],
      defaultLineId: 'default',
    );
  }

  factory NiumaMediaSource.lines({
    required List<MediaLine> lines,
    required String defaultLineId,
  }) {
    if (lines.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'must not be empty');
    }
    if (!lines.any((l) => l.id == defaultLineId)) {
      throw ArgumentError.value(
        defaultLineId,
        'defaultLineId',
        'is not the id of any provided line',
      );
    }
    return NiumaMediaSource._(lines: lines, defaultLineId: defaultLineId);
  }

  final List<MediaLine> lines;
  final String defaultLineId;

  MediaLine get currentLine => lines.firstWhere((l) => l.id == defaultLineId);

  MediaLine? lineById(String id) {
    for (final line in lines) {
      if (line.id == id) return line;
    }
    return null;
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/multi_source_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/multi_source.dart test/orchestration/multi_source_test.dart
git commit -m "feat(orchestration): NiumaMediaSource with single + lines factories"
```

---

## Task 7: MultiSourcePolicy

**Files:**
- Modify: `lib/src/orchestration/multi_source.dart`
- Test: `test/orchestration/multi_source_test.dart`

- [ ] **Step 1: Failing test**

```dart
test('MultiSourcePolicy.autoFailover defaults', () {
  const p = MultiSourcePolicy.autoFailover();
  expect(p.maxAttempts, 1);
  expect(p.enabled, isTrue);
});

test('MultiSourcePolicy.manual disables failover', () {
  const p = MultiSourcePolicy.manual();
  expect(p.enabled, isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/multi_source_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Append to `multi_source.dart`:

```dart
@immutable
class MultiSourcePolicy {
  const MultiSourcePolicy._({
    required this.enabled,
    required this.maxAttempts,
  });

  const factory MultiSourcePolicy.autoFailover({int maxAttempts}) =
      _AutoFailover;
  const factory MultiSourcePolicy.manual() = _Manual;

  final bool enabled;
  final int maxAttempts;
}

class _AutoFailover extends MultiSourcePolicy {
  const _AutoFailover({int maxAttempts = 1})
      : super._(enabled: true, maxAttempts: maxAttempts);
}

class _Manual extends MultiSourcePolicy {
  const _Manual() : super._(enabled: false, maxAttempts: 0);
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/multi_source_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/multi_source.dart test/orchestration/multi_source_test.dart
git commit -m "feat(orchestration): MultiSourcePolicy.autoFailover + manual"
```

---

## Task 8: ResumeStorage abstract + FakeResumeStorage

**Files:**
- Create: `lib/src/orchestration/resume_position.dart`
- Create: `lib/src/testing/fake_resume_storage.dart`
- Test: `test/orchestration/resume_position_test.dart`

- [ ] **Step 1: Failing test**

```dart
// test/orchestration/resume_position_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/resume_position.dart';
import 'package:niuma_player/src/testing/fake_resume_storage.dart';

void main() {
  test('FakeResumeStorage round-trips a position', () async {
    final s = FakeResumeStorage();
    expect(await s.read('k'), isNull);
    await s.write('k', const Duration(seconds: 30));
    expect(await s.read('k'), const Duration(seconds: 30));
    await s.clear('k');
    expect(await s.read('k'), isNull);
  });

  test('FakeResumeStorage isolates keys', () async {
    final s = FakeResumeStorage();
    await s.write('a', const Duration(seconds: 5));
    await s.write('b', const Duration(seconds: 10));
    expect(await s.read('a'), const Duration(seconds: 5));
    expect(await s.read('b'), const Duration(seconds: 10));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/resume_position_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/src/orchestration/resume_position.dart
abstract class ResumeStorage {
  const ResumeStorage();
  Future<Duration?> read(String key);
  Future<void> write(String key, Duration position);
  Future<void> clear(String key);
}
```

```dart
// lib/src/testing/fake_resume_storage.dart
import '../orchestration/resume_position.dart';

class FakeResumeStorage implements ResumeStorage {
  final Map<String, Duration> _store = {};

  @override
  Future<Duration?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, Duration position) async {
    _store[key] = position;
  }

  @override
  Future<void> clear(String key) async {
    _store.remove(key);
  }

  Map<String, Duration> get snapshot => Map.unmodifiable(_store);
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/resume_position_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/resume_position.dart lib/src/testing/fake_resume_storage.dart test/orchestration/resume_position_test.dart
git commit -m "feat(orchestration,testing): ResumeStorage abstract + FakeResumeStorage"
```

---

## Task 9: SharedPreferencesResumeStorage

**Files:**
- Modify: `lib/src/orchestration/resume_position.dart`
- Modify: `pubspec.yaml`
- Test: `test/orchestration/resume_position_test.dart`

- [ ] **Step 1: Add explicit shared_preferences dep**

Edit `pubspec.yaml`, under `dependencies:` (alphabetical):

```yaml
  shared_preferences: ^2.2.0
```

Run: `flutter pub get`

- [ ] **Step 2: Failing test**

Append to `test/orchestration/resume_position_test.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

// inside main():
test('SharedPreferencesResumeStorage round-trips via SharedPreferences', () async {
  SharedPreferences.setMockInitialValues({});
  const s = SharedPreferencesResumeStorage();

  await s.write('video:abc', const Duration(seconds: 42));
  expect(await s.read('video:abc'), const Duration(seconds: 42));

  await s.clear('video:abc');
  expect(await s.read('video:abc'), isNull);
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/orchestration/resume_position_test.dart`
Expected: FAIL — `SharedPreferencesResumeStorage` not defined.

- [ ] **Step 4: Implement**

Append to `resume_position.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesResumeStorage extends ResumeStorage {
  const SharedPreferencesResumeStorage({this.prefix = 'niuma_player.resume.'});

  final String prefix;

  String _k(String key) => '$prefix$key';

  @override
  Future<Duration?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_k(key));
    if (ms == null) return null;
    return Duration(milliseconds: ms);
  }

  @override
  Future<void> write(String key, Duration position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_k(key), position.inMilliseconds);
  }

  @override
  Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_k(key));
  }
}
```

- [ ] **Step 5: Run tests**

Run: `flutter test test/orchestration/resume_position_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml lib/src/orchestration/resume_position.dart test/orchestration/resume_position_test.dart
git commit -m "feat(orchestration): SharedPreferencesResumeStorage default impl"
```

---

## Task 10: ResumePolicy + ResumeBehaviour

**Files:**
- Modify: `lib/src/orchestration/resume_position.dart`
- Test: `test/orchestration/resume_position_test.dart`

- [ ] **Step 1: Failing test**

```dart
test('ResumePolicy defaults', () {
  const p = ResumePolicy();
  expect(p.behaviour, ResumeBehaviour.auto);
  expect(p.minSavedPosition, const Duration(seconds: 30));
  expect(p.discardIfNearEnd, const Duration(seconds: 30));
  expect(p.savePeriod, const Duration(seconds: 5));
});

test('ResumePolicy.defaultKeyOf hashes uri', () {
  final ds = NiumaDataSource.network('https://cdn/x.mp4');
  expect(defaultResumeKey(ds), 'video:https://cdn/x.mp4');
});
```

Add `import 'package:niuma_player/src/domain/data_source.dart';` at top if missing.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/resume_position_test.dart`
Expected: FAIL — `ResumePolicy`, `ResumeBehaviour`, `defaultResumeKey` not defined.

- [ ] **Step 3: Implement**

Append to `resume_position.dart`:

```dart
import '../domain/data_source.dart';

enum ResumeBehaviour {
  auto,
  askUser,
  disabled,
}

typedef ResumeKeyOf = String Function(NiumaDataSource source);

String defaultResumeKey(NiumaDataSource source) => 'video:${source.uri}';

@immutable
class ResumePolicy {
  const ResumePolicy({
    this.storage = const SharedPreferencesResumeStorage(),
    this.keyOf = defaultResumeKey,
    this.behaviour = ResumeBehaviour.auto,
    this.minSavedPosition = const Duration(seconds: 30),
    this.discardIfNearEnd = const Duration(seconds: 30),
    this.savePeriod = const Duration(seconds: 5),
  });

  final ResumeStorage storage;
  final ResumeKeyOf keyOf;
  final ResumeBehaviour behaviour;
  final Duration minSavedPosition;
  final Duration discardIfNearEnd;
  final Duration savePeriod;
}
```

Add `import 'package:flutter/foundation.dart';` if missing.

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/resume_position_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/resume_position.dart test/orchestration/resume_position_test.dart
git commit -m "feat(orchestration): ResumePolicy + ResumeBehaviour + defaultResumeKey"
```

---

## Task 11: RetryPolicy

**Files:**
- Create: `lib/src/orchestration/retry_policy.dart`
- Test: `test/orchestration/retry_policy_test.dart`

- [ ] **Step 1: Failing test**

```dart
// test/orchestration/retry_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/orchestration/retry_policy.dart';

void main() {
  test('RetryPolicy.smart retries network + transient, skips codec/terminal', () {
    const p = RetryPolicy.smart();
    expect(p.shouldRetry(PlayerErrorCategory.network, attempt: 1), isTrue);
    expect(p.shouldRetry(PlayerErrorCategory.transient, attempt: 1), isTrue);
    expect(p.shouldRetry(PlayerErrorCategory.codecUnsupported, attempt: 1),
        isFalse);
    expect(p.shouldRetry(PlayerErrorCategory.terminal, attempt: 1), isFalse);
  });

  test('RetryPolicy.smart caps at maxAttempts (default 3)', () {
    const p = RetryPolicy.smart();
    expect(p.shouldRetry(PlayerErrorCategory.network, attempt: 3), isTrue);
    expect(p.shouldRetry(PlayerErrorCategory.network, attempt: 4), isFalse);
  });

  test('RetryPolicy.exponential backoff doubles up to max', () {
    const p = RetryPolicy.exponential(
      base: Duration(seconds: 1),
      max: Duration(seconds: 10),
    );
    expect(p.delayFor(1), const Duration(seconds: 1));
    expect(p.delayFor(2), const Duration(seconds: 2));
    expect(p.delayFor(3), const Duration(seconds: 4));
    expect(p.delayFor(4), const Duration(seconds: 8));
    expect(p.delayFor(5), const Duration(seconds: 10)); // capped
  });

  test('RetryPolicy.none never retries', () {
    const p = RetryPolicy.none();
    expect(p.shouldRetry(PlayerErrorCategory.network, attempt: 1), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/retry_policy_test.dart`
Expected: FAIL — `retry_policy.dart` not defined.

- [ ] **Step 3: Implement**

```dart
// lib/src/orchestration/retry_policy.dart
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/player_state.dart';

@immutable
class RetryPolicy {
  const RetryPolicy._({
    required this.maxAttempts,
    required this.base,
    required this.max,
    required this.retryCategories,
  });

  const factory RetryPolicy.smart({int maxAttempts}) = _SmartRetry;
  const factory RetryPolicy.exponential({
    Duration base,
    Duration max,
    int maxAttempts,
  }) = _ExponentialRetry;
  const factory RetryPolicy.none() = _NoRetry;

  final int maxAttempts;
  final Duration base;
  final Duration max;
  final Set<PlayerErrorCategory> retryCategories;

  bool shouldRetry(PlayerErrorCategory category, {required int attempt}) {
    if (attempt > maxAttempts) return false;
    return retryCategories.contains(category);
  }

  Duration delayFor(int attempt) {
    final exp = base * pow(2, attempt - 1).toInt();
    return exp > max ? max : exp;
  }
}

class _SmartRetry extends RetryPolicy {
  const _SmartRetry({int maxAttempts = 3})
      : super._(
          maxAttempts: maxAttempts,
          base: const Duration(seconds: 1),
          max: const Duration(seconds: 10),
          retryCategories: const {
            PlayerErrorCategory.network,
            PlayerErrorCategory.transient,
          },
        );
}

class _ExponentialRetry extends RetryPolicy {
  const _ExponentialRetry({
    Duration base = const Duration(seconds: 1),
    Duration max = const Duration(seconds: 10),
    int maxAttempts = 3,
  }) : super._(
          maxAttempts: maxAttempts,
          base: base,
          max: max,
          retryCategories: const {
            PlayerErrorCategory.network,
            PlayerErrorCategory.transient,
          },
        );
}

class _NoRetry extends RetryPolicy {
  const _NoRetry()
      : super._(
          maxAttempts: 0,
          base: Duration.zero,
          max: Duration.zero,
          retryCategories: const {},
        );
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/retry_policy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/retry_policy.dart test/orchestration/retry_policy_test.dart
git commit -m "feat(orchestration): RetryPolicy.smart / exponential / none"
```

---

## Task 12: FakeAnalyticsEmitter test double

**Files:**
- Create: `lib/src/testing/fake_analytics_emitter.dart`
- Test: `test/testing/fake_analytics_emitter_test.dart`

- [ ] **Step 1: Failing test**

```dart
// test/testing/fake_analytics_emitter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/observability/analytics_event.dart';
import 'package:niuma_player/src/testing/fake_analytics_emitter.dart';

void main() {
  test('FakeAnalyticsEmitter records events in order', () {
    final fake = FakeAnalyticsEmitter();
    fake.call(const AnalyticsEvent.adClick(cueType: AdCueType.preRoll));
    fake.call(const AnalyticsEvent.adImpression(
      cueType: AdCueType.preRoll,
      durationShown: Duration(seconds: 5),
    ));
    expect(fake.events, hasLength(2));
    expect(fake.events.first, isA<AdClick>());
  });

  test('FakeAnalyticsEmitter.clear empties log', () {
    final fake = FakeAnalyticsEmitter()
      ..call(const AnalyticsEvent.adClick(cueType: AdCueType.preRoll));
    fake.clear();
    expect(fake.events, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/testing/fake_analytics_emitter_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/src/testing/fake_analytics_emitter.dart
import '../observability/analytics_event.dart';

class FakeAnalyticsEmitter {
  final List<AnalyticsEvent> _events = [];
  List<AnalyticsEvent> get events => List.unmodifiable(_events);

  void call(AnalyticsEvent event) => _events.add(event);

  void clear() => _events.clear();
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/testing/fake_analytics_emitter_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/testing/fake_analytics_emitter.dart test/testing/fake_analytics_emitter_test.dart
git commit -m "feat(testing): FakeAnalyticsEmitter capturing test double"
```

---

## Task 13: lib/testing.dart public export

**Files:**
- Create: `lib/testing.dart`

- [ ] **Step 1: Create file**

```dart
// lib/testing.dart

/// Public test doubles for niuma_player consumers' widget tests.
/// Import as `package:niuma_player/testing.dart`.
library;

export 'src/testing/fake_resume_storage.dart';
export 'src/testing/fake_analytics_emitter.dart';
```

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/testing.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/testing.dart
git commit -m "feat(testing): expose Fake* doubles via lib/testing.dart"
```

---

## Task 14: AdCue + AdController abstract

**Files:**
- Create: `lib/src/orchestration/ad_schedule.dart`
- Test: `test/orchestration/ad_schedule_test.dart`

- [ ] **Step 1: Failing test**

```dart
// test/orchestration/ad_schedule_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/ad_schedule.dart';

void main() {
  test('AdCue defaults', () {
    final cue = AdCue(builder: (_, __) => const SizedBox());
    expect(cue.minDisplayDuration, const Duration(seconds: 5));
    expect(cue.timeout, isNull);
    expect(cue.dismissOnTap, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/ad_schedule_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/src/orchestration/ad_schedule.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

abstract class AdController {
  /// Closes the ad. Calls before [AdCue.minDisplayDuration] are silently
  /// ignored in release builds and asserted in debug builds.
  void dismiss();

  /// How long the ad has been displayed.
  Duration get elapsed;
  Stream<Duration> get elapsedStream;

  void reportImpression();
  void reportClick();
}

@immutable
class AdCue {
  const AdCue({
    required this.builder,
    this.minDisplayDuration = const Duration(seconds: 5),
    this.timeout,
    this.dismissOnTap = false,
  });

  final Widget Function(BuildContext, AdController) builder;
  final Duration minDisplayDuration;
  final Duration? timeout;
  final bool dismissOnTap;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/ad_schedule_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/ad_schedule.dart test/orchestration/ad_schedule_test.dart
git commit -m "feat(orchestration): AdCue + AdController abstract"
```

---

## Task 15: NiumaAdSchedule + MidRollAd + enums

**Files:**
- Modify: `lib/src/orchestration/ad_schedule.dart`
- Test: `test/orchestration/ad_schedule_test.dart`

- [ ] **Step 1: Failing test**

```dart
test('NiumaAdSchedule defaults', () {
  const s = NiumaAdSchedule();
  expect(s.preRoll, isNull);
  expect(s.midRolls, isEmpty);
  expect(s.pauseAd, isNull);
  expect(s.postRoll, isNull);
  expect(s.pauseAdShowPolicy, PauseAdShowPolicy.oncePerSession);
});

test('MidRollAd default skipPolicy is skipIfSeekedPast', () {
  final m = MidRollAd(
    at: const Duration(seconds: 30),
    cue: AdCue(builder: (_, __) => const SizedBox()),
  );
  expect(m.skipPolicy, MidRollSkipPolicy.skipIfSeekedPast);
  expect(m.at, const Duration(seconds: 30));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/ad_schedule_test.dart`
Expected: FAIL — types not defined.

- [ ] **Step 3: Implement**

Append to `ad_schedule.dart`:

```dart
enum MidRollSkipPolicy {
  fireOnce,
  fireEachPass,
  skipIfSeekedPast,
}

enum PauseAdShowPolicy {
  always,
  oncePerSession,
  cooldown,
}

@immutable
class MidRollAd {
  const MidRollAd({
    required this.at,
    required this.cue,
    this.skipPolicy = MidRollSkipPolicy.skipIfSeekedPast,
  });

  final Duration at;
  final AdCue cue;
  final MidRollSkipPolicy skipPolicy;
}

@immutable
class NiumaAdSchedule {
  const NiumaAdSchedule({
    this.preRoll,
    this.midRolls = const <MidRollAd>[],
    this.pauseAd,
    this.postRoll,
    this.pauseAdShowPolicy = PauseAdShowPolicy.oncePerSession,
    this.pauseAdCooldown = const Duration(minutes: 1),
  });

  final AdCue? preRoll;
  final List<MidRollAd> midRolls;
  final AdCue? pauseAd;
  final AdCue? postRoll;
  final PauseAdShowPolicy pauseAdShowPolicy;
  final Duration pauseAdCooldown;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/ad_schedule_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/ad_schedule.dart test/orchestration/ad_schedule_test.dart
git commit -m "feat(orchestration): NiumaAdSchedule + MidRollAd + ad enums"
```

---

## Task 16: AdSchedulerOrchestrator — preRoll path

**Files:**
- Create: `lib/src/orchestration/ad_scheduler.dart`
- Test: `test/orchestration/ad_scheduler_test.dart`

This task introduces the orchestrator with **only** preRoll handling. midRoll / pauseAd / postRoll come in subsequent tasks.

- [ ] **Step 1: Set up test scaffolding + failing test**

```dart
// test/orchestration/ad_scheduler_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/orchestration/ad_schedule.dart';
import 'package:niuma_player/src/orchestration/ad_scheduler.dart';
import 'package:niuma_player/src/testing/fake_analytics_emitter.dart';

class _FakePlayer extends ChangeNotifier
    implements ValueListenable<NiumaPlayerValue> {
  NiumaPlayerValue _v = NiumaPlayerValue.uninitialized();

  @override
  NiumaPlayerValue get value => _v;

  bool playCalled = false;
  bool pauseCalled = false;

  void emit(NiumaPlayerValue v) {
    _v = v;
    notifyListeners();
  }

  void play() => playCalled = true;
  void pause() => pauseCalled = true;
}

void main() {
  test('preRoll fires on phase idle → ready transition', () {
    final player = _FakePlayer();
    final analytics = FakeAnalyticsEmitter();
    final orch = AdSchedulerOrchestrator(
      schedule: NiumaAdSchedule(
        preRoll: AdCue(builder: (_, __) => const SizedBox()),
      ),
      playerValue: player,
      onPlay: player.play,
      onPause: player.pause,
      analytics: analytics.call,
    )..attach();

    expect(orch.activeCue.value, isNull);

    player.emit(NiumaPlayerValue.uninitialized()
        .copyWith(phase: PlayerPhase.ready));

    expect(orch.activeCue.value, isNotNull);
    expect(analytics.events,
        contains(isA<AnalyticsEvent>().having(
            (e) => e.toString(), 'is AdScheduled', contains('AdScheduled'))));
    orch.dispose();
  });
}
```

(Note: the test imports `AnalyticsEvent`; add `import 'package:niuma_player/src/observability/analytics_event.dart';` at top.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/ad_scheduler_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement (preRoll only)**

```dart
// lib/src/orchestration/ad_scheduler.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../domain/player_state.dart';
import '../observability/analytics_emitter.dart';
import '../observability/analytics_event.dart';
import 'ad_schedule.dart';

typedef _Cb = void Function();

class AdSchedulerOrchestrator {
  AdSchedulerOrchestrator({
    required this.schedule,
    required this.playerValue,
    required this.onPlay,
    required this.onPause,
    AnalyticsEmitter? analytics,
  }) : _analytics = analytics;

  final NiumaAdSchedule schedule;
  final ValueListenable<NiumaPlayerValue> playerValue;
  final _Cb onPlay;
  final _Cb onPause;
  final AnalyticsEmitter? _analytics;

  final ValueNotifier<AdCue?> activeCue = ValueNotifier(null);

  PlayerPhase? _lastPhase;
  bool _preRollFired = false;

  void attach() {
    playerValue.addListener(_onValue);
  }

  void dispose() {
    playerValue.removeListener(_onValue);
    activeCue.dispose();
  }

  void _onValue() {
    final phase = playerValue.value.phase;
    final transitionedToReady =
        _lastPhase != PlayerPhase.ready && phase == PlayerPhase.ready;
    _lastPhase = phase;

    if (transitionedToReady && !_preRollFired && schedule.preRoll != null) {
      _preRollFired = true;
      _fire(schedule.preRoll!, AdCueType.preRoll);
    }
  }

  bool _wasPlaying = false;
  void _fire(AdCue cue, AdCueType type) {
    _wasPlaying = playerValue.value.isPlaying;
    if (_wasPlaying) onPause();
    activeCue.value = cue;
    _analytics?.call(AnalyticsEvent.adScheduled(cueType: type));
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/ad_scheduler_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/ad_scheduler.dart test/orchestration/ad_scheduler_test.dart
git commit -m "feat(orchestration): AdSchedulerOrchestrator with preRoll firing"
```

---

## Task 17: AdSchedulerOrchestrator — midRoll path + skipIfSeekedPast

**Files:**
- Modify: `lib/src/orchestration/ad_scheduler.dart`
- Test: `test/orchestration/ad_scheduler_test.dart`

- [ ] **Step 1: Failing test**

Append:

```dart
test('midRoll fires when position naturally crosses .at', () {
  final player = _FakePlayer();
  final orch = AdSchedulerOrchestrator(
    schedule: NiumaAdSchedule(
      midRolls: [
        MidRollAd(
          at: const Duration(seconds: 30),
          cue: AdCue(builder: (_, __) => const SizedBox()),
        ),
      ],
    ),
    playerValue: player,
    onPlay: player.play,
    onPause: player.pause,
  )..attach();

  // Initial playing at t=29s; no fire.
  player.emit(NiumaPlayerValue.uninitialized().copyWith(
    phase: PlayerPhase.playing,
    position: const Duration(seconds: 29),
  ));
  expect(orch.activeCue.value, isNull);

  // t=31s; fire.
  player.emit(NiumaPlayerValue.uninitialized().copyWith(
    phase: PlayerPhase.playing,
    position: const Duration(seconds: 31),
  ));
  expect(orch.activeCue.value, isNotNull);
  orch.dispose();
});

test('midRoll skipIfSeekedPast: jump from t=10 to t=40 does not fire midRoll@30', () {
  final player = _FakePlayer();
  final orch = AdSchedulerOrchestrator(
    schedule: NiumaAdSchedule(
      midRolls: [
        MidRollAd(
          at: const Duration(seconds: 30),
          cue: AdCue(builder: (_, __) => const SizedBox()),
          // default = skipIfSeekedPast
        ),
      ],
    ),
    playerValue: player,
    onPlay: player.play,
    onPause: player.pause,
  )..attach();

  // Establish baseline at t=10.
  player.emit(NiumaPlayerValue.uninitialized().copyWith(
    phase: PlayerPhase.playing,
    position: const Duration(seconds: 10),
  ));
  // Big jump to t=40 (≥ 2s gap → treat as seek).
  player.emit(NiumaPlayerValue.uninitialized().copyWith(
    phase: PlayerPhase.playing,
    position: const Duration(seconds: 40),
  ));
  expect(orch.activeCue.value, isNull,
      reason: 'skipIfSeekedPast should suppress midRoll on jumps');
  orch.dispose();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/ad_scheduler_test.dart`
Expected: FAIL — midRoll not handled yet.

- [ ] **Step 3: Implement**

In `ad_scheduler.dart`, replace `_onValue` and add tracking:

```dart
  Duration _lastPos = Duration.zero;
  final Set<int> _midRollFired = {};

  void _onValue() {
    final v = playerValue.value;
    final phase = v.phase;

    final transitionedToReady =
        _lastPhase != PlayerPhase.ready && phase == PlayerPhase.ready;
    if (transitionedToReady && !_preRollFired && schedule.preRoll != null) {
      _preRollFired = true;
      _fire(schedule.preRoll!, AdCueType.preRoll);
    }

    // midRoll
    final pos = v.position;
    final delta = pos - _lastPos;
    final isLikelySeek = delta > const Duration(seconds: 2) ||
        delta < Duration.zero;

    for (var i = 0; i < schedule.midRolls.length; i++) {
      if (_midRollFired.contains(i)) continue;
      final mr = schedule.midRolls[i];
      final crossedNow = _lastPos < mr.at && pos >= mr.at;
      if (!crossedNow) continue;

      switch (mr.skipPolicy) {
        case MidRollSkipPolicy.fireOnce:
          _midRollFired.add(i);
          _fire(mr.cue, AdCueType.midRoll);
        case MidRollSkipPolicy.fireEachPass:
          _fire(mr.cue, AdCueType.midRoll);
        case MidRollSkipPolicy.skipIfSeekedPast:
          if (isLikelySeek) {
            _midRollFired.add(i); // mark fired to prevent later natural cross
          } else {
            _midRollFired.add(i);
            _fire(mr.cue, AdCueType.midRoll);
          }
      }
    }

    _lastPos = pos;
    _lastPhase = phase;
  }
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/ad_scheduler_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/ad_scheduler.dart test/orchestration/ad_scheduler_test.dart
git commit -m "feat(orchestration): AdScheduler midRoll + skipIfSeekedPast"
```

---

## Task 18: AdSchedulerOrchestrator — pauseAd + frequency policy

**Files:**
- Modify: `lib/src/orchestration/ad_scheduler.dart`
- Test: `test/orchestration/ad_scheduler_test.dart`

- [ ] **Step 1: Failing test**

```dart
test('pauseAd fires on playing → paused (manual)', () {
  final player = _FakePlayer();
  final orch = AdSchedulerOrchestrator(
    schedule: NiumaAdSchedule(
      pauseAd: AdCue(builder: (_, __) => const SizedBox()),
    ),
    playerValue: player,
    onPlay: player.play,
    onPause: player.pause,
  )..attach();

  player.emit(NiumaPlayerValue.uninitialized()
      .copyWith(phase: PlayerPhase.playing));
  player.emit(NiumaPlayerValue.uninitialized()
      .copyWith(phase: PlayerPhase.paused));
  expect(orch.activeCue.value, isNotNull);

  orch.dispose();
});

test('PauseAdShowPolicy.oncePerSession suppresses second pause', () {
  final player = _FakePlayer();
  final orch = AdSchedulerOrchestrator(
    schedule: NiumaAdSchedule(
      pauseAd: AdCue(builder: (_, __) => const SizedBox()),
      pauseAdShowPolicy: PauseAdShowPolicy.oncePerSession,
    ),
    playerValue: player,
    onPlay: player.play,
    onPause: player.pause,
  )..attach();

  // First pause.
  player.emit(NiumaPlayerValue.uninitialized()
      .copyWith(phase: PlayerPhase.playing));
  player.emit(NiumaPlayerValue.uninitialized()
      .copyWith(phase: PlayerPhase.paused));
  orch.activeCue.value = null; // simulate dismiss

  // Second pause — should NOT fire.
  player.emit(NiumaPlayerValue.uninitialized()
      .copyWith(phase: PlayerPhase.playing));
  player.emit(NiumaPlayerValue.uninitialized()
      .copyWith(phase: PlayerPhase.paused));
  expect(orch.activeCue.value, isNull);

  orch.dispose();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/ad_scheduler_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Add fields to `AdSchedulerOrchestrator`:

```dart
  int _pauseAdShownCount = 0;
  DateTime? _pauseAdLastShownAt;
```

Add to `_onValue`, after the midRoll block:

```dart
    // pauseAd: detect manual pause (playing → paused).
    final justPaused = _lastPhase == PlayerPhase.playing &&
        phase == PlayerPhase.paused;
    if (justPaused && schedule.pauseAd != null && _shouldShowPauseAd()) {
      _fire(schedule.pauseAd!, AdCueType.pauseAd);
      _pauseAdShownCount++;
      _pauseAdLastShownAt = DateTime.now();
    }
```

Add the helper:

```dart
  bool _shouldShowPauseAd() {
    switch (schedule.pauseAdShowPolicy) {
      case PauseAdShowPolicy.always:
        return true;
      case PauseAdShowPolicy.oncePerSession:
        return _pauseAdShownCount == 0;
      case PauseAdShowPolicy.cooldown:
        if (_pauseAdLastShownAt == null) return true;
        return DateTime.now().difference(_pauseAdLastShownAt!) >=
            schedule.pauseAdCooldown;
    }
  }
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/ad_scheduler_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/ad_scheduler.dart test/orchestration/ad_scheduler_test.dart
git commit -m "feat(orchestration): AdScheduler pauseAd + frequency policies"
```

---

## Task 19: AdSchedulerOrchestrator — postRoll + AdControllerImpl

**Files:**
- Modify: `lib/src/orchestration/ad_scheduler.dart`
- Test: `test/orchestration/ad_scheduler_test.dart`

- [ ] **Step 1: Failing tests**

```dart
test('postRoll fires on phase=ended', () {
  final player = _FakePlayer();
  final orch = AdSchedulerOrchestrator(
    schedule: NiumaAdSchedule(
      postRoll: AdCue(builder: (_, __) => const SizedBox()),
    ),
    playerValue: player,
    onPlay: player.play,
    onPause: player.pause,
  )..attach();

  player.emit(NiumaPlayerValue.uninitialized()
      .copyWith(phase: PlayerPhase.ended));
  expect(orch.activeCue.value, isNotNull);
  orch.dispose();
});

test('AdController.dismiss() before minDisplayDuration is ignored', () {
  final cue = AdCue(
    builder: (_, __) => const SizedBox(),
    minDisplayDuration: const Duration(seconds: 5),
  );
  final ctl = AdControllerImpl(cue: cue, onDismiss: () {});
  ctl.dismiss(); // 0s elapsed
  expect(ctl.dismissed, isFalse, reason: 'release builds silently ignore');
});

test('AdController.dismiss after minDisplayDuration completes', () {
  final cue = AdCue(
    builder: (_, __) => const SizedBox(),
    minDisplayDuration: const Duration(seconds: 5),
  );
  var dismissed = false;
  final ctl = AdControllerImpl(cue: cue, onDismiss: () {
    dismissed = true;
  });
  ctl.simulateElapsed(const Duration(seconds: 6));
  ctl.dismiss();
  expect(dismissed, isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/ad_scheduler_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Add `AdControllerImpl` class and postRoll handling:

```dart
class AdControllerImpl implements AdController {
  AdControllerImpl({required this.cue, required this.onDismiss});

  final AdCue cue;
  final VoidCallback onDismiss;
  final _elapsedCtrl = StreamController<Duration>.broadcast();
  final _start = DateTime.now();
  Duration _simulatedElapsed = Duration.zero;
  bool dismissed = false;

  @override
  Duration get elapsed =>
      _simulatedElapsed > Duration.zero
          ? _simulatedElapsed
          : DateTime.now().difference(_start);

  @override
  Stream<Duration> get elapsedStream => _elapsedCtrl.stream;

  @visibleForTesting
  void simulateElapsed(Duration d) => _simulatedElapsed = d;

  @override
  void dismiss() {
    if (elapsed < cue.minDisplayDuration) {
      assert(false,
          'AdController.dismiss() called before minDisplayDuration; ignoring.');
      return;
    }
    if (dismissed) return;
    dismissed = true;
    onDismiss();
    _elapsedCtrl.close();
  }

  @override
  void reportImpression() {}

  @override
  void reportClick() {}
}
```

In `_onValue`, add:

```dart
    if (_lastPhase != PlayerPhase.ended &&
        phase == PlayerPhase.ended &&
        schedule.postRoll != null) {
      _fire(schedule.postRoll!, AdCueType.postRoll);
    }
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/ad_scheduler_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/ad_scheduler.dart test/orchestration/ad_scheduler_test.dart
git commit -m "feat(orchestration): AdScheduler postRoll + AdControllerImpl with min-display gate"
```

---

## Task 20: ResumeOrchestrator

**Files:**
- Modify: `lib/src/orchestration/resume_position.dart`
- Test: `test/orchestration/resume_position_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:fake_async/fake_async.dart';
// in main():
test('ResumeOrchestrator reads on init and seeks to saved position', () async {
  final storage = FakeResumeStorage();
  await storage.write('key', const Duration(seconds: 42));

  Duration? seekTarget;
  final ds = NiumaDataSource.network('https://x');
  final orch = ResumeOrchestrator(
    policy: ResumePolicy(
      storage: storage,
      keyOf: (_) => 'key',
    ),
    source: ds,
    seekTo: (d) async => seekTarget = d,
    currentPosition: () => Duration.zero,
  );

  await orch.onInitialized();
  expect(seekTarget, const Duration(seconds: 42));
});

test('ResumeOrchestrator does not write before minSavedPosition', () {
  fakeAsync((async) {
    final storage = FakeResumeStorage();
    var pos = Duration.zero;
    final orch = ResumeOrchestrator(
      policy: ResumePolicy(
        storage: storage,
        keyOf: (_) => 'k',
        minSavedPosition: const Duration(seconds: 30),
        savePeriod: const Duration(seconds: 5),
      ),
      source: NiumaDataSource.network('x'),
      seekTo: (_) async {},
      currentPosition: () => pos,
    )..startPeriodicSave();

    pos = const Duration(seconds: 10);
    async.elapse(const Duration(seconds: 6));
    expect(storage.snapshot, isEmpty);

    pos = const Duration(seconds: 31);
    async.elapse(const Duration(seconds: 6));
    expect(storage.snapshot['k'], const Duration(seconds: 31));

    orch.dispose();
  });
});
```

Add `import 'package:fake_async/fake_async.dart';` and `import 'package:niuma_player/src/domain/data_source.dart';` if missing.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/resume_position_test.dart`
Expected: FAIL — `ResumeOrchestrator` not defined.

- [ ] **Step 3: Implement**

Append to `resume_position.dart`:

```dart
import 'dart:async';

class ResumeOrchestrator {
  ResumeOrchestrator({
    required this.policy,
    required this.source,
    required this.seekTo,
    required this.currentPosition,
  });

  final ResumePolicy policy;
  final NiumaDataSource source;
  final Future<void> Function(Duration) seekTo;
  final Duration Function() currentPosition;

  Timer? _saveTimer;
  String get _key => policy.keyOf(source);

  Future<void> onInitialized() async {
    if (policy.behaviour == ResumeBehaviour.disabled) return;
    final saved = await policy.storage.read(_key);
    if (saved == null) return;
    if (policy.behaviour == ResumeBehaviour.auto) {
      await seekTo(saved);
    }
    // askUser: caller is responsible for invoking onResumePrompt.
  }

  void startPeriodicSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(policy.savePeriod, (_) => _saveIfApplicable());
  }

  Future<void> _saveIfApplicable() async {
    final pos = currentPosition();
    if (pos < policy.minSavedPosition) return;
    await policy.storage.write(_key, pos);
  }

  Future<void> onEnded() async {
    await policy.storage.clear(_key);
  }

  Future<void> dispose() async {
    _saveTimer?.cancel();
    final pos = currentPosition();
    if (pos >= policy.minSavedPosition) {
      await policy.storage.write(_key, pos);
    }
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/resume_position_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/resume_position.dart test/orchestration/resume_position_test.dart
git commit -m "feat(orchestration): ResumeOrchestrator with periodic save + ended clear"
```

---

## Task 21: AutoFailoverOrchestrator

**Files:**
- Create: `lib/src/orchestration/auto_failover.dart`
- Test: `test/orchestration/auto_failover_test.dart`

- [ ] **Step 1: Failing test**

```dart
// test/orchestration/auto_failover_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/orchestration/auto_failover.dart';
import 'package:niuma_player/src/orchestration/multi_source.dart';

void main() {
  test('picks next priority line on network error', () {
    final lines = [
      MediaLine(
        id: 'a',
        label: 'A',
        priority: 0,
        source: NiumaDataSource.network('https://a'),
      ),
      MediaLine(
        id: 'b',
        label: 'B',
        priority: 1,
        source: NiumaDataSource.network('https://b'),
      ),
    ];
    final orch = AutoFailoverOrchestrator(
      lines: lines,
      policy: const MultiSourcePolicy.autoFailover(maxAttempts: 1),
    );
    expect(orch.nextLine(currentId: 'a',
        category: PlayerErrorCategory.network), 'b');
  });

  test('does NOT switch on codecUnsupported', () {
    final lines = [
      MediaLine(id: 'a', label: 'A', source: NiumaDataSource.network('a')),
      MediaLine(id: 'b', label: 'B', source: NiumaDataSource.network('b')),
    ];
    final orch = AutoFailoverOrchestrator(
      lines: lines,
      policy: const MultiSourcePolicy.autoFailover(),
    );
    expect(orch.nextLine(currentId: 'a',
        category: PlayerErrorCategory.codecUnsupported), isNull);
  });

  test('returns null after maxAttempts reached', () {
    final lines = [
      MediaLine(id: 'a', label: 'A', source: NiumaDataSource.network('a')),
      MediaLine(id: 'b', label: 'B', source: NiumaDataSource.network('b')),
    ];
    final orch = AutoFailoverOrchestrator(
      lines: lines,
      policy: const MultiSourcePolicy.autoFailover(maxAttempts: 1),
    );
    orch.recordFailover();
    expect(orch.nextLine(currentId: 'a',
        category: PlayerErrorCategory.network), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/orchestration/auto_failover_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// lib/src/orchestration/auto_failover.dart
import '../domain/player_state.dart';
import 'multi_source.dart';

class AutoFailoverOrchestrator {
  AutoFailoverOrchestrator({required this.lines, required this.policy});

  final List<MediaLine> lines;
  final MultiSourcePolicy policy;

  int _failovers = 0;

  void recordFailover() => _failovers++;

  String? nextLine({
    required String currentId,
    required PlayerErrorCategory category,
  }) {
    if (!policy.enabled) return null;
    if (_failovers >= policy.maxAttempts) return null;
    if (category != PlayerErrorCategory.network &&
        category != PlayerErrorCategory.terminal) {
      return null;
    }

    final sorted = [...lines]..sort((a, b) => b.priority.compareTo(a.priority));
    final currentIdx = sorted.indexWhere((l) => l.id == currentId);
    if (currentIdx == -1) return null;
    if (currentIdx + 1 >= sorted.length) return null;
    return sorted[currentIdx + 1].id;
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/orchestration/auto_failover_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orchestration/auto_failover.dart test/orchestration/auto_failover_test.dart
git commit -m "feat(orchestration): AutoFailoverOrchestrator picks next priority line"
```

---

## Task 22: New kernel events: LineSwitching / LineSwitched / LineSwitchFailed

**Files:**
- Modify: `lib/src/domain/player_state.dart`

- [ ] **Step 1: Add the three event classes**

Append to `lib/src/domain/player_state.dart`, in the same sealed-class neighborhood as `BackendSelected` / `FallbackTriggered`:

```dart
final class LineSwitching extends NiumaPlayerEvent {
  const LineSwitching({required this.fromId, required this.toId});
  final String fromId;
  final String toId;

  @override
  String toString() => 'LineSwitching(from: $fromId, to: $toId)';
}

final class LineSwitched extends NiumaPlayerEvent {
  const LineSwitched(this.toId);
  final String toId;

  @override
  String toString() => 'LineSwitched(to: $toId)';
}

final class LineSwitchFailed extends NiumaPlayerEvent {
  const LineSwitchFailed({required this.toId, required this.error});
  final String toId;
  final Object error;

  @override
  String toString() => 'LineSwitchFailed(to: $toId, error: $error)';
}
```

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze lib/src/domain/player_state.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/src/domain/player_state.dart
git commit -m "feat(kernel): add LineSwitching/LineSwitched/LineSwitchFailed events"
```

---

## Task 23: Migrate NiumaPlayerController to NiumaMediaSource (additive)

**Files:**
- Modify: `lib/src/presentation/niuma_player_controller.dart`
- Modify: `test/state_machine_test.dart`
- Modify: `example/lib/player_page.dart` (if it constructs `NiumaPlayerController` directly)

The controller currently accepts `NiumaDataSource`. We make it accept `NiumaMediaSource` and provide a `.dataSource(NiumaDataSource)` factory for back-compat.

- [ ] **Step 1: Read current controller signature**

Run: `head -70 lib/src/presentation/niuma_player_controller.dart`
Note the constructor + `dataSource` field.

- [ ] **Step 2: Modify the controller**

Replace the relevant block with:

```dart
import '../orchestration/multi_source.dart';

// inside class NiumaPlayerController:
NiumaPlayerController(
  this.source, {
  NiumaPlayerOptions? options,
  PlatformBridge? platform,
  BackendFactory? backendFactory,
})  : options = options ?? const NiumaPlayerOptions(),
      _platform = platform ?? const DefaultPlatformBridge(),
      _backendFactory = backendFactory ?? const DefaultBackendFactory(),
      super(NiumaPlayerValue.uninitialized());

factory NiumaPlayerController.dataSource(
  NiumaDataSource ds, {
  NiumaPlayerOptions? options,
  PlatformBridge? platform,
  BackendFactory? backendFactory,
}) =>
    NiumaPlayerController(
      NiumaMediaSource.single(ds),
      options: options,
      platform: platform,
      backendFactory: backendFactory,
    );

final NiumaMediaSource source;

/// Backwards-compatible accessor for callers that only use a single line.
NiumaDataSource get dataSource => source.currentLine.source;
```

In `_runInitialize()` and `_initNative()`, change every reference to `dataSource` to `source.currentLine.source` if needed (or keep using the `dataSource` getter, since it returns `currentLine.source`).

- [ ] **Step 3: Update existing tests**

In `test/state_machine_test.dart`, replace any:

```dart
NiumaPlayerController(NiumaDataSource.network(...), ...)
```

with:

```dart
NiumaPlayerController.dataSource(NiumaDataSource.network(...), ...)
```

Run: `flutter test test/state_machine_test.dart`
Expected: PASS (no behaviour change).

- [ ] **Step 4: Update example**

If `example/lib/player_page.dart` constructs the controller directly, switch to `.dataSource(...)` factory.

Run: `cd example && flutter analyze`
Expected: No issues.

- [ ] **Step 5: Verify global analyze + tests**

Run: `flutter analyze && flutter test`
Expected: All clean / pass.

- [ ] **Step 6: Commit**

```bash
git add lib/src/presentation/niuma_player_controller.dart test/state_machine_test.dart example/lib/player_page.dart
git commit -m "refactor(kernel): controller accepts NiumaMediaSource; .dataSource factory keeps single-source ergonomics"
```

---

## Task 24: Wire SourceMiddleware pipeline into controller.initialize()

**Files:**
- Modify: `lib/src/presentation/niuma_player_controller.dart`
- Modify: `test/state_machine_test.dart`

- [ ] **Step 1: Failing test**

Add to `test/state_machine_test.dart`:

```dart
test('middleware pipeline runs before backend.initialize() — header injected',
    () async {
  final fake = FakeBackendFactory();
  final ctrl = NiumaPlayerController(
    NiumaMediaSource.single(
      NiumaDataSource.network('https://cdn/x.mp4', headers: {'X': '1'}),
    ),
    middlewares: const [
      HeaderInjectionMiddleware({'Y': '2'}),
    ],
    platform: FakePlatformBridge(isIOS: true),
    backendFactory: fake,
  );
  await ctrl.initialize();
  // FakeBackendFactory should record the source it was constructed with.
  expect(fake.lastSourceFromMiddleware?.headers, {'X': '1', 'Y': '2'});
  ctrl.dispose();
});
```

(Add `import 'package:niuma_player/src/orchestration/source_middleware.dart';` and `import 'package:niuma_player/src/orchestration/multi_source.dart';` to the test file.)

Make sure `FakeBackendFactory` records the resolved `NiumaDataSource` it received in `createVideoPlayer`/`createNative`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state_machine_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `niuma_player_controller.dart`:

```dart
import '../orchestration/source_middleware.dart';

NiumaPlayerController(
  this.source, {
  this.middlewares = const [],
  // ... rest
});

final List<SourceMiddleware> middlewares;

NiumaDataSource _resolvedSource = const _PlaceholderSource();

Future<NiumaDataSource> _resolveSource() async {
  return runSourceMiddlewares(source.currentLine.source, middlewares);
}
```

Update `_runInitialize()` to call `_resolvedSource = await _resolveSource()` first, then pass `_resolvedSource` to the backend factory instead of `dataSource`.

The backend factory signatures already accept `NiumaDataSource`, so update the call sites only:

```dart
await _attachBackend(_backendFactory.createVideoPlayer(_resolvedSource));
// ...
await _attachBackend(_backendFactory.createNative(_resolvedSource, forceIjk: forceIjk));
```

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/src/presentation/niuma_player_controller.dart test/state_machine_test.dart
git commit -m "feat(kernel): controller runs SourceMiddleware pipeline before backend"
```

---

## Task 25: controller.switchLine(id)

**Files:**
- Modify: `lib/src/presentation/niuma_player_controller.dart`
- Modify: `test/state_machine_test.dart`

- [ ] **Step 1: Failing test**

```dart
test('switchLine: dispose old backend, init new at saved position', () async {
  final fake = FakeBackendFactory();
  final lineA = MediaLine(
    id: 'a',
    label: 'A',
    source: NiumaDataSource.network('https://a'),
  );
  final lineB = MediaLine(
    id: 'b',
    label: 'B',
    source: NiumaDataSource.network('https://b'),
  );
  final ctrl = NiumaPlayerController(
    NiumaMediaSource.lines(lines: [lineA, lineB], defaultLineId: 'a'),
    platform: FakePlatformBridge(isIOS: true),
    backendFactory: fake,
  );
  await ctrl.initialize();
  fake.simulatePosition(const Duration(seconds: 12));

  final events = <NiumaPlayerEvent>[];
  ctrl.events.listen(events.add);

  await ctrl.switchLine('b');

  expect(events.any((e) => e is LineSwitching && e.toId == 'b'), isTrue);
  expect(events.any((e) => e is LineSwitched && e.toId == 'b'), isTrue);
  expect(fake.lastSeekTarget, const Duration(seconds: 12));
  ctrl.dispose();
});
```

(Augment `FakeBackendFactory` to expose `simulatePosition` and `lastSeekTarget`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state_machine_test.dart`
Expected: FAIL — `switchLine` not defined.

- [ ] **Step 3: Implement**

```dart
Future<void> switchLine(String lineId) async {
  if (_disposed) return;
  final target = source.lineById(lineId);
  if (target == null) {
    throw ArgumentError.value(lineId, 'lineId', 'unknown line id');
  }
  final fromId = _activeLineId ?? source.defaultLineId;
  if (fromId == lineId) return;

  _emit(LineSwitching(fromId: fromId, toId: lineId));

  final savedPos = value.position;
  final wasPlaying = value.isPlaying;

  try {
    await _disposeCurrentBackend();
    _activeLineId = lineId;
    final resolved = await runSourceMiddlewares(target.source, middlewares);
    _resolvedSource = resolved;

    // Build the right backend for this platform / forceIjk policy.
    if (_platform.isIOS || _platform.isWeb) {
      await _attachBackend(_backendFactory.createVideoPlayer(resolved));
      await _backend!.initialize().timeout(options.initTimeout);
    } else {
      await _initNative(forceIjk: options.forceIjkOnAndroid);
    }

    if (savedPos > Duration.zero) {
      await _backend!.seekTo(savedPos);
    }
    if (wasPlaying) {
      await _backend!.play();
    }
    _emit(LineSwitched(lineId));
  } catch (e) {
    _emit(LineSwitchFailed(toId: lineId, error: e));
    rethrow;
  }
}

String? _activeLineId;
```

(Make sure `_initNative` no longer reads `dataSource` directly; use `_resolvedSource` consistently.)

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/src/presentation/niuma_player_controller.dart test/state_machine_test.dart
git commit -m "feat(kernel): controller.switchLine with seek-restore + line events"
```

---

## Task 26: Apply RetryPolicy on initialize() failure

**Files:**
- Modify: `lib/src/presentation/niuma_player_controller.dart`
- Modify: `test/state_machine_test.dart`

- [ ] **Step 1: Failing test**

```dart
test('RetryPolicy.smart retries network error twice then succeeds', () async {
  final fake = FakeBackendFactory()
    ..nativeAttempts = [
      _Throw(PlayerErrorCategory.network),
      _Throw(PlayerErrorCategory.network),
      _Succeed(),
    ];
  final ctrl = NiumaPlayerController(
    NiumaMediaSource.single(NiumaDataSource.network('https://x')),
    retryPolicy: const RetryPolicy.smart(maxAttempts: 3),
    platform: FakePlatformBridge(isIOS: false), // Android route
    backendFactory: fake,
  );
  await ctrl.initialize();
  expect(fake.nativeForceIjkArgs, hasLength(3));
});

test('RetryPolicy does not retry codecUnsupported', () async {
  final fake = FakeBackendFactory()
    ..nativeAttempts = [_Throw(PlayerErrorCategory.codecUnsupported)];
  final ctrl = NiumaPlayerController(
    NiumaMediaSource.single(NiumaDataSource.network('https://x')),
    retryPolicy: const RetryPolicy.smart(),
    platform: FakePlatformBridge(isIOS: false),
    backendFactory: fake,
  );
  await expectLater(ctrl.initialize(), throwsA(anything));
  expect(fake.nativeForceIjkArgs, hasLength(2)); // existing forceIjk fallback retry
});
```

(`_Throw` and `_Succeed` are local helper classes that drive `FakeBackendFactory`'s programmed responses.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state_machine_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `niuma_player_controller.dart`:

```dart
import '../orchestration/retry_policy.dart';

NiumaPlayerController(
  this.source, {
  this.middlewares = const [],
  this.retryPolicy = const RetryPolicy.smart(),
  // ...
});

final RetryPolicy retryPolicy;
```

Wrap the inner-most `await native.initialize()` (or `await _backend!.initialize()`) in a retry loop:

```dart
Future<void> _initializeWithRetry(Future<void> Function() bringUp) async {
  var attempt = 1;
  while (true) {
    try {
      await bringUp();
      return;
    } catch (e) {
      final category = _categorize(e);
      if (!retryPolicy.shouldRetry(category, attempt: attempt)) rethrow;
      await Future<void>.delayed(retryPolicy.delayFor(attempt));
      attempt++;
    }
  }
}

PlayerErrorCategory _categorize(Object e) {
  if (e is TimeoutException) return PlayerErrorCategory.network;
  // Existing path: native errors propagate as PlatformException strings; we
  // categorize known signatures here. Default to unknown.
  return PlayerErrorCategory.unknown;
}
```

Use `_initializeWithRetry` to wrap the *single-line attempt* (NOT the existing forceIjk Try-Fail-Remember loop on Android — that stays). Keep both layers: retry first (transient/network), then if exhausted, the existing forceIjk fallback runs.

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/src/presentation/niuma_player_controller.dart test/state_machine_test.dart
git commit -m "feat(kernel): apply RetryPolicy around backend.initialize"
```

---

## Task 27: Public exports

**Files:**
- Modify: `lib/niuma_player.dart`

- [ ] **Step 1: Add exports**

Replace existing exports with:

```dart
// kernel
export 'src/data/default_backend_factory.dart' show DefaultBackendFactory;
export 'src/data/default_platform_bridge.dart' show DefaultPlatformBridge;
export 'src/data/device_memory.dart';
export 'src/domain/backend_factory.dart' show BackendFactory;
export 'src/domain/data_source.dart';
export 'src/domain/platform_bridge.dart' show PlatformBridge;
export 'src/domain/player_backend.dart' show PlayerBackend, PlayerBackendKind;
export 'src/domain/player_state.dart'
    show
        NiumaPlayerValue,
        PlayerPhase,
        PlayerError,
        PlayerErrorCategory,
        NiumaPlayerEvent,
        BackendSelected,
        FallbackTriggered,
        FallbackReason,
        LineSwitching,
        LineSwitched,
        LineSwitchFailed;
export 'src/presentation/niuma_player_controller.dart';
export 'src/presentation/niuma_player_view.dart';

// orchestration
export 'src/orchestration/multi_source.dart'
    show
        MediaQuality,
        MediaLine,
        NiumaMediaSource,
        MultiSourcePolicy;
export 'src/orchestration/source_middleware.dart'
    show
        SourceMiddleware,
        HeaderInjectionMiddleware,
        SignedUrlMiddleware,
        runSourceMiddlewares;
export 'src/orchestration/resume_position.dart'
    show
        ResumeStorage,
        SharedPreferencesResumeStorage,
        ResumePolicy,
        ResumeBehaviour,
        ResumeKeyOf,
        defaultResumeKey,
        ResumeOrchestrator;
export 'src/orchestration/retry_policy.dart' show RetryPolicy;
export 'src/orchestration/ad_schedule.dart'
    show
        AdCue,
        AdController,
        NiumaAdSchedule,
        MidRollAd,
        MidRollSkipPolicy,
        PauseAdShowPolicy;
export 'src/orchestration/ad_scheduler.dart' show AdSchedulerOrchestrator;
export 'src/orchestration/auto_failover.dart' show AutoFailoverOrchestrator;

// observability
export 'src/observability/analytics_event.dart'
    show
        AnalyticsEvent,
        AdScheduled,
        AdImpression,
        AdClick,
        AdDismissed,
        AdCueType,
        AdDismissReason;
export 'src/observability/analytics_emitter.dart' show AnalyticsEmitter;
```

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/niuma_player.dart
git commit -m "feat: export M7 orchestration + observability public API"
```

---

## Task 28: Update CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Edit changelog**

Replace `## [Unreleased]` block:

```markdown
## [Unreleased]

### Added (M7 — orchestration layer)
- `NiumaMediaSource` (single + lines factories), `MediaLine`, `MediaQuality`
- `MultiSourcePolicy.autoFailover(maxAttempts: 1)` (default) / `manual()`
- `controller.switchLine(id)` with `LineSwitching` / `LineSwitched` / `LineSwitchFailed` events
- `AutoFailoverOrchestrator` — picks next priority line on `network` / `terminal` errors
- `SourceMiddleware`, `HeaderInjectionMiddleware`, `SignedUrlMiddleware`, `runSourceMiddlewares`
- `ResumeStorage`, `SharedPreferencesResumeStorage`, `ResumePolicy`, `ResumeOrchestrator`
- `RetryPolicy.smart()` / `.exponential()` / `.none()`
- `AdCue`, `AdController`, `NiumaAdSchedule`, `MidRollAd`, `AdSchedulerOrchestrator` (preRoll / midRoll w/ skipPolicy / pauseAd w/ frequency / postRoll)
- `AnalyticsEvent` sealed hierarchy + `AnalyticsEmitter` typedef
- Public test doubles via `package:niuma_player/testing.dart`: `FakeResumeStorage`, `FakeAnalyticsEmitter`

### Changed
- `NiumaPlayerController` first arg type: `NiumaDataSource` → `NiumaMediaSource`. Use `NiumaPlayerController.dataSource(ds)` factory for the single-source case (drop-in for old code).
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: log M7 orchestration + observability under [Unreleased]"
```

---

## Task 29: Final sanity

- [ ] **Step 1: Full analyze**

Run: `flutter analyze`
Expected: 0 issues.

- [ ] **Step 2: Full test**

Run: `flutter test`
Expected: All pass (kernel 14 + new orchestration tests).

- [ ] **Step 3: dartdoc dry run**

Run: `dart doc --dry-run`
Expected: 0 warnings, 0 errors.

- [ ] **Step 4: Pub publish dry run**

Run: `flutter pub publish --dry-run 2>&1 | grep -B1 -A3 "^\*"`
Expected: only the unavoidable "modified in git" warning.

- [ ] **Step 5: Build smoke (Android debug + Web)**

Run:
```bash
cd example
flutter build apk --debug
flutter build web
```
Expected: Both succeed.

- [ ] **Step 6: Commit any remaining incidental fixes**

```bash
git status   # should be clean or only stale .lock changes
```

If anything was changed during sanity step, commit it under a clear message.

---

## Self-Review

Spec coverage check (Section ↔ Task):

| Spec Section | Task(s) |
|---|---|
| 1. Layer architecture | files materialized in Task 1–21, `lib/testing.dart` Task 13 |
| 2. Public API of NiumaVideoPlayer | **out of scope** (M9) |
| 3. Gesture arbiter | **out of scope** (M8) |
| 4. Lifecycle | **out of scope** (M8) |
| 4.7 Background audio | **out of scope** (M6) |
| 5. Ad cue system | Task 14 (types) + 15 (schedule) + 16–19 (scheduler) + 25 (analytics) |
| 6.1 Multi-source | Task 5 + 6 + 7 (types) + 21 (failover) + 22 (events) + 25 (switchLine) |
| 6.2 Resume | Task 8 + 9 + 10 (types) + 20 (orchestrator) |
| 6.3 VTT thumbnail | **out of scope** (M8) |
| 6.4 Source middleware | Task 2 + 3 + 4 (impl) + 24 (wire into kernel) |
| 7.3 Test doubles | Task 8 + 12 + 13 |
| Section 9 Out of Scope | excluded by intent |

All M7-relevant spec sections have at least one task. Sections labelled out-of-scope are intentionally deferred to M8/M9/M6 plans.

Placeholder scan: none. All steps have concrete code.

Type consistency:
- `NiumaMediaSource.lineById` introduced in Task 6; used in Task 25 ✓
- `AdControllerImpl.dismiss` defined in Task 19; AdSchedulerOrchestrator integrates in Task 25-pending — covered when wiring AnalyticsEmitter passes through `AdSchedulerOrchestrator.fire` (already accepts emitter in Task 16; midRoll/pauseAd/postRoll inherit it via the same `_fire`).
- `RetryPolicy.delayFor` returns `Duration`, used by Task 26's retry loop ✓
- `AutoFailoverOrchestrator.nextLine` returns `String?`; Task 25 wiring is M8-side, but the orchestrator is fully tested standalone in Task 21.

No drift detected.
