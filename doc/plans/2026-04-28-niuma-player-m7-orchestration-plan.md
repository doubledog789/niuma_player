# M7 编排层 — 实施计划

> **执行方式**：必备子 skill：用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务推进本计划。步骤用复选框 `- [ ]` 跟踪。

**目标**：构建纯 Dart 编排层（`lib/src/orchestration/` + `lib/src/observability/` + 初版 `lib/src/testing/` 测试替身），并接通 kernel 触点（`NiumaPlayerController` 上的多源切换 + middleware + retry）。

**架构**：新增五个编排单元（multi-source、resume、retry、ads、source middleware），加上一个 analytics 事件 hook。每个单元由 value class（数据）+ orchestrator（行为）组成。kernel 的 `NiumaPlayerController` 第一参数改为 `NiumaMediaSource`，新增可选 `middlewares:` / `retryPolicy:` 参数和 `switchLine(id)` 方法。编排层全部纯 Dart，无需 platform channel 即可单测。

**技术栈**：Dart、`flutter_test`、`fake_async`、`shared_preferences`（已通过依赖树进入 pubspec — 这里显式声明）。

**Spec 参考**：`doc/plans/2026-04-27-niuma-player-enterprise-dart-design.md` 第 1、5、6、7.3 节。

---

## 文件结构

### 新增文件

```
lib/src/observability/
├── analytics_event.dart                  AnalyticsEvent sealed 类层级
└── analytics_emitter.dart                AnalyticsEmitter typedef

lib/src/orchestration/
├── source_middleware.dart                SourceMiddleware abstract + HeaderInjection + SignedUrl + pipeline runner
├── multi_source.dart                     MediaQuality, MediaLine, NiumaMediaSource, MultiSourcePolicy
├── resume_position.dart                  ResumeStorage, ResumePolicy, ResumeBehaviour, ResumeOrchestrator
├── retry_policy.dart                     RetryPolicy value class
├── ad_schedule.dart                      AdCue, AdController, NiumaAdSchedule, MidRollAd, ad enums
├── ad_scheduler.dart                     AdSchedulerOrchestrator（行为）
└── auto_failover.dart                    AutoFailoverOrchestrator（行为）

lib/src/testing/
├── fake_resume_storage.dart              内存版 ResumeStorage，供测试用
└── fake_analytics_emitter.dart           捕获式 AnalyticsEmitter，供测试用

lib/testing.dart                          公开测试替身导出

test/orchestration/
├── source_middleware_test.dart
├── multi_source_test.dart
├── resume_position_test.dart
├── retry_policy_test.dart
├── ad_schedule_test.dart
├── ad_scheduler_test.dart
└── auto_failover_test.dart
```

### 修改的文件

```
lib/src/presentation/niuma_player_controller.dart
   ↳ 接受 `NiumaMediaSource` + `middlewares` + `retryPolicy`；新增 `switchLine`
   ↳ 抛 LineSwitching / LineSwitched / LineSwitchFailed 事件
lib/src/domain/player_state.dart
   ↳ 新增 LineSwitching / LineSwitched / LineSwitchFailed 事件子类
lib/niuma_player.dart
   ↳ 导出新增的 orchestration / observability API
test/state_machine_test.dart
   ↳ 迁移到 NiumaMediaSource.single(NiumaDataSource(...)) 形式
example/lib/player_page.dart
   ↳ 同上迁移
pubspec.yaml
   ↳ 显式声明 shared_preferences
CHANGELOG.md
   ↳ 在 [Unreleased] 下记录 M7 新增内容
```

---

## Task 1：Analytics 事件层级

**文件**：
- 新建：`lib/src/observability/analytics_event.dart`
- 新建：`lib/src/observability/analytics_emitter.dart`
- 测试：`test/orchestration/analytics_event_test.dart`

- [ ] **步骤 1：先写失败测试**

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/analytics_event_test.dart`
预期：失败 — `analytics_event.dart` 不存在。

- [ ] **步骤 3：实现 `AnalyticsEvent`**

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

/// 业务方传入的回调。niuma_player 在每个内部事件上调用此函数；
/// app 自行转发到自己的埋点 SDK（神策 / GIO / Bugly / ...）。
typedef AnalyticsEmitter = void Function(AnalyticsEvent event);
```

- [ ] **步骤 4：跑测试确认通过**

执行：`flutter test test/orchestration/analytics_event_test.dart`
预期：通过 — 两个 case 都绿。

- [ ] **步骤 5：提交**

```bash
git add lib/src/observability/ test/orchestration/analytics_event_test.dart
git commit -m "feat(observability): add AnalyticsEvent sealed hierarchy + AnalyticsEmitter typedef"
```

---

## Task 2：SourceMiddleware abstract + HeaderInjection

**文件**：
- 新建：`lib/src/orchestration/source_middleware.dart`
- 测试：`test/orchestration/source_middleware_test.dart`

- [ ] **步骤 1：先写失败测试**

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/source_middleware_test.dart`
预期：失败 — `source_middleware.dart` 不存在。

- [ ] **步骤 3：实现 abstract + HeaderInjectionMiddleware**

```dart
// lib/src/orchestration/source_middleware.dart
import '../domain/data_source.dart';

/// 在 [NiumaDataSource] 抵达 backend 之前对其变换。
/// 在 initialize / switchLine / retry 时各运行一次 —— 每次访问网络
/// 都能拿到新的签名 URL / 新的 header。
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

- [ ] **步骤 4：跑测试确认通过**

执行：`flutter test test/orchestration/source_middleware_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/source_middleware.dart test/orchestration/source_middleware_test.dart
git commit -m "feat(orchestration): SourceMiddleware abstract + HeaderInjectionMiddleware"
```

---

## Task 3：SignedUrlMiddleware

**文件**：
- 修改：`lib/src/orchestration/source_middleware.dart`
- 测试：`test/orchestration/source_middleware_test.dart`

- [ ] **步骤 1：追加失败测试**

在 `test/orchestration/source_middleware_test.dart` 末尾追加：

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/source_middleware_test.dart`
预期：失败 — `SignedUrlMiddleware` 未定义。

- [ ] **步骤 3：实现**

在 `lib/src/orchestration/source_middleware.dart` 末尾追加：

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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/source_middleware_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/source_middleware.dart test/orchestration/source_middleware_test.dart
git commit -m "feat(orchestration): SignedUrlMiddleware"
```

---

## Task 4：Middleware pipeline runner

**文件**：
- 修改：`lib/src/orchestration/source_middleware.dart`
- 测试：`test/orchestration/source_middleware_test.dart`

- [ ] **步骤 1：追加失败测试**

追加：

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/source_middleware_test.dart`
预期：失败 — `runSourceMiddlewares` 未定义。

- [ ] **步骤 3：实现**

在 `source_middleware.dart` 末尾追加：

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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/source_middleware_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/source_middleware.dart test/orchestration/source_middleware_test.dart
git commit -m "feat(orchestration): runSourceMiddlewares pipeline"
```

---

## Task 5：MediaQuality + MediaLine value class

**文件**：
- 新建：`lib/src/orchestration/multi_source.dart`
- 测试：`test/orchestration/multi_source_test.dart`

- [ ] **步骤 1：失败测试**

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/multi_source_test.dart`
预期：失败。

- [ ] **步骤 3：实现**

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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/multi_source_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/multi_source.dart test/orchestration/multi_source_test.dart
git commit -m "feat(orchestration): MediaQuality + MediaLine value classes"
```

---

## Task 6：NiumaMediaSource（single + lines factory）

**文件**：
- 修改：`lib/src/orchestration/multi_source.dart`
- 测试：`test/orchestration/multi_source_test.dart`

- [ ] **步骤 1：失败测试**

追加：

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/multi_source_test.dart`
预期：失败 — `NiumaMediaSource` 未定义。

- [ ] **步骤 3：实现**

在 `multi_source.dart` 末尾追加：

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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/multi_source_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/multi_source.dart test/orchestration/multi_source_test.dart
git commit -m "feat(orchestration): NiumaMediaSource with single + lines factories"
```

---

## Task 7：MultiSourcePolicy

**文件**：
- 修改：`lib/src/orchestration/multi_source.dart`
- 测试：`test/orchestration/multi_source_test.dart`

- [ ] **步骤 1：失败测试**

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/multi_source_test.dart`
预期：失败。

- [ ] **步骤 3：实现**

在 `multi_source.dart` 末尾追加：

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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/multi_source_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/multi_source.dart test/orchestration/multi_source_test.dart
git commit -m "feat(orchestration): MultiSourcePolicy.autoFailover + manual"
```

---

## Task 8：ResumeStorage abstract + FakeResumeStorage

**文件**：
- 新建：`lib/src/orchestration/resume_position.dart`
- 新建：`lib/src/testing/fake_resume_storage.dart`
- 测试：`test/orchestration/resume_position_test.dart`

- [ ] **步骤 1：失败测试**

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/resume_position_test.dart`
预期：失败。

- [ ] **步骤 3：实现**

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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/resume_position_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/resume_position.dart lib/src/testing/fake_resume_storage.dart test/orchestration/resume_position_test.dart
git commit -m "feat(orchestration,testing): ResumeStorage abstract + FakeResumeStorage"
```

---

## Task 9：SharedPreferencesResumeStorage

**文件**：
- 修改：`lib/src/orchestration/resume_position.dart`
- 修改：`pubspec.yaml`
- 测试：`test/orchestration/resume_position_test.dart`

- [ ] **步骤 1：显式声明 shared_preferences 依赖**

编辑 `pubspec.yaml`，在 `dependencies:` 下（按字母序）：

```yaml
  shared_preferences: ^2.2.0
```

执行：`flutter pub get`

- [ ] **步骤 2：失败测试**

在 `test/orchestration/resume_position_test.dart` 末尾追加：

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

- [ ] **步骤 3：跑测试确认失败**

执行：`flutter test test/orchestration/resume_position_test.dart`
预期：失败 — `SharedPreferencesResumeStorage` 未定义。

- [ ] **步骤 4：实现**

在 `resume_position.dart` 末尾追加：

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

- [ ] **步骤 5：跑测试**

执行：`flutter test test/orchestration/resume_position_test.dart`
预期：通过。

- [ ] **步骤 6：提交**

```bash
git add pubspec.yaml lib/src/orchestration/resume_position.dart test/orchestration/resume_position_test.dart
git commit -m "feat(orchestration): SharedPreferencesResumeStorage default impl"
```

---

## Task 10：ResumePolicy + ResumeBehaviour

**文件**：
- 修改：`lib/src/orchestration/resume_position.dart`
- 测试：`test/orchestration/resume_position_test.dart`

- [ ] **步骤 1：失败测试**

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

如缺失，在文件顶部加 `import 'package:niuma_player/src/domain/data_source.dart';`。

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/resume_position_test.dart`
预期：失败 — `ResumePolicy` / `ResumeBehaviour` / `defaultResumeKey` 未定义。

- [ ] **步骤 3：实现**

在 `resume_position.dart` 末尾追加：

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

如缺失，加 `import 'package:flutter/foundation.dart';`。

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/resume_position_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/resume_position.dart test/orchestration/resume_position_test.dart
git commit -m "feat(orchestration): ResumePolicy + ResumeBehaviour + defaultResumeKey"
```

---

## Task 11：RetryPolicy

**文件**：
- 新建：`lib/src/orchestration/retry_policy.dart`
- 测试：`test/orchestration/retry_policy_test.dart`

- [ ] **步骤 1：失败测试**

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/retry_policy_test.dart`
预期：失败 — `retry_policy.dart` 未定义。

- [ ] **步骤 3：实现**

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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/retry_policy_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/retry_policy.dart test/orchestration/retry_policy_test.dart
git commit -m "feat(orchestration): RetryPolicy.smart / exponential / none"
```

---

## Task 12：FakeAnalyticsEmitter 测试替身

**文件**：
- 新建：`lib/src/testing/fake_analytics_emitter.dart`
- 测试：`test/testing/fake_analytics_emitter_test.dart`

- [ ] **步骤 1：失败测试**

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/testing/fake_analytics_emitter_test.dart`
预期：失败。

- [ ] **步骤 3：实现**

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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/testing/fake_analytics_emitter_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/testing/fake_analytics_emitter.dart test/testing/fake_analytics_emitter_test.dart
git commit -m "feat(testing): FakeAnalyticsEmitter capturing test double"
```

---

## Task 13：lib/testing.dart 公开导出

**文件**：
- 新建：`lib/testing.dart`

- [ ] **步骤 1：建文件**

```dart
// lib/testing.dart

/// 给 niuma_player 业务方在 widget 测试中使用的公开测试替身。
/// 通过 `package:niuma_player/testing.dart` 导入。
library;

export 'src/testing/fake_resume_storage.dart';
export 'src/testing/fake_analytics_emitter.dart';
```

- [ ] **步骤 2：analyze 检查**

执行：`flutter analyze lib/testing.dart`
预期：无 issue。

- [ ] **步骤 3：提交**

```bash
git add lib/testing.dart
git commit -m "feat(testing): expose Fake* doubles via lib/testing.dart"
```

---

## Task 14：AdCue + AdController abstract

**文件**：
- 新建：`lib/src/orchestration/ad_schedule.dart`
- 测试：`test/orchestration/ad_schedule_test.dart`

- [ ] **步骤 1：失败测试**

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/ad_schedule_test.dart`
预期：失败。

- [ ] **步骤 3：实现**

```dart
// lib/src/orchestration/ad_schedule.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

abstract class AdController {
  /// 关闭广告。在 [AdCue.minDisplayDuration] 之前调用：release 构建静默忽略，
  /// debug 构建 assert。
  void dismiss();

  /// 广告已展示了多久。
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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/ad_schedule_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/ad_schedule.dart test/orchestration/ad_schedule_test.dart
git commit -m "feat(orchestration): AdCue + AdController abstract"
```

---

## Task 15：NiumaAdSchedule + MidRollAd + enum

**文件**：
- 修改：`lib/src/orchestration/ad_schedule.dart`
- 测试：`test/orchestration/ad_schedule_test.dart`

- [ ] **步骤 1：失败测试**

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/ad_schedule_test.dart`
预期：失败 — 类型未定义。

- [ ] **步骤 3：实现**

在 `ad_schedule.dart` 末尾追加：

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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/ad_schedule_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/ad_schedule.dart test/orchestration/ad_schedule_test.dart
git commit -m "feat(orchestration): NiumaAdSchedule + MidRollAd + ad enums"
```

---

## Task 16：AdSchedulerOrchestrator — preRoll 路径

**文件**：
- 新建：`lib/src/orchestration/ad_scheduler.dart`
- 测试：`test/orchestration/ad_scheduler_test.dart`

本任务只引入 orchestrator 与 **preRoll** 处理。midRoll / pauseAd / postRoll 留给后续任务。

- [ ] **步骤 1：搭测试脚手架 + 失败测试**

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

（注：测试 import `AnalyticsEvent`；在顶部加 `import 'package:niuma_player/src/observability/analytics_event.dart';`。）

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/ad_scheduler_test.dart`
预期：失败。

- [ ] **步骤 3：实现（仅 preRoll）**

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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/ad_scheduler_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/ad_scheduler.dart test/orchestration/ad_scheduler_test.dart
git commit -m "feat(orchestration): AdSchedulerOrchestrator with preRoll firing"
```

---

## Task 17：AdSchedulerOrchestrator — midRoll 路径 + skipIfSeekedPast

**文件**：
- 修改：`lib/src/orchestration/ad_scheduler.dart`
- 测试：`test/orchestration/ad_scheduler_test.dart`

- [ ] **步骤 1：失败测试**

追加：

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

  // 起始 t=29s 播放中；不触发。
  player.emit(NiumaPlayerValue.uninitialized().copyWith(
    phase: PlayerPhase.playing,
    position: const Duration(seconds: 29),
  ));
  expect(orch.activeCue.value, isNull);

  // t=31s；触发。
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

  // 在 t=10 建立基线。
  player.emit(NiumaPlayerValue.uninitialized().copyWith(
    phase: PlayerPhase.playing,
    position: const Duration(seconds: 10),
  ));
  // 大跳到 t=40（≥ 2s 间隔 → 视作 seek）。
  player.emit(NiumaPlayerValue.uninitialized().copyWith(
    phase: PlayerPhase.playing,
    position: const Duration(seconds: 40),
  ));
  expect(orch.activeCue.value, isNull,
      reason: 'skipIfSeekedPast should suppress midRoll on jumps');
  orch.dispose();
});
```

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/ad_scheduler_test.dart`
预期：失败 — midRoll 还没处理。

- [ ] **步骤 3：实现**

在 `ad_scheduler.dart` 中替换 `_onValue` 并添加状态字段：

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
            _midRollFired.add(i); // 标记已 fired，防止后续自然跨越再触发
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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/ad_scheduler_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/ad_scheduler.dart test/orchestration/ad_scheduler_test.dart
git commit -m "feat(orchestration): AdScheduler midRoll + skipIfSeekedPast"
```

---

## Task 18：AdSchedulerOrchestrator — pauseAd + 频次策略

**文件**：
- 修改：`lib/src/orchestration/ad_scheduler.dart`
- 测试：`test/orchestration/ad_scheduler_test.dart`

- [ ] **步骤 1：失败测试**

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

  // 第一次暂停。
  player.emit(NiumaPlayerValue.uninitialized()
      .copyWith(phase: PlayerPhase.playing));
  player.emit(NiumaPlayerValue.uninitialized()
      .copyWith(phase: PlayerPhase.paused));
  orch.activeCue.value = null; // 模拟 dismiss

  // 第二次暂停 — 不该触发。
  player.emit(NiumaPlayerValue.uninitialized()
      .copyWith(phase: PlayerPhase.playing));
  player.emit(NiumaPlayerValue.uninitialized()
      .copyWith(phase: PlayerPhase.paused));
  expect(orch.activeCue.value, isNull);

  orch.dispose();
});
```

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/ad_scheduler_test.dart`
预期：失败。

- [ ] **步骤 3：实现**

给 `AdSchedulerOrchestrator` 加字段：

```dart
  int _pauseAdShownCount = 0;
  DateTime? _pauseAdLastShownAt;
```

在 `_onValue` 的 midRoll 处理之后追加：

```dart
    // pauseAd：检测手动暂停（playing → paused）。
    final justPaused = _lastPhase == PlayerPhase.playing &&
        phase == PlayerPhase.paused;
    if (justPaused && schedule.pauseAd != null && _shouldShowPauseAd()) {
      _fire(schedule.pauseAd!, AdCueType.pauseAd);
      _pauseAdShownCount++;
      _pauseAdLastShownAt = DateTime.now();
    }
```

加上辅助方法：

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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/ad_scheduler_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/ad_scheduler.dart test/orchestration/ad_scheduler_test.dart
git commit -m "feat(orchestration): AdScheduler pauseAd + frequency policies"
```

---

## Task 19：AdSchedulerOrchestrator — postRoll + AdControllerImpl

**文件**：
- 修改：`lib/src/orchestration/ad_scheduler.dart`
- 测试：`test/orchestration/ad_scheduler_test.dart`

- [ ] **步骤 1：失败测试**

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/ad_scheduler_test.dart`
预期：失败。

- [ ] **步骤 3：实现**

加 `AdControllerImpl` 类与 postRoll 处理：

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

在 `_onValue` 中追加：

```dart
    if (_lastPhase != PlayerPhase.ended &&
        phase == PlayerPhase.ended &&
        schedule.postRoll != null) {
      _fire(schedule.postRoll!, AdCueType.postRoll);
    }
```

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/ad_scheduler_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/ad_scheduler.dart test/orchestration/ad_scheduler_test.dart
git commit -m "feat(orchestration): AdScheduler postRoll + AdControllerImpl with min-display gate"
```

---

## Task 20：ResumeOrchestrator

**文件**：
- 修改：`lib/src/orchestration/resume_position.dart`
- 测试：`test/orchestration/resume_position_test.dart`

- [ ] **步骤 1：失败测试**

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

如缺失，加 `import 'package:fake_async/fake_async.dart';` 与 `import 'package:niuma_player/src/domain/data_source.dart';`。

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/resume_position_test.dart`
预期：失败 — `ResumeOrchestrator` 未定义。

- [ ] **步骤 3：实现**

在 `resume_position.dart` 末尾追加：

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
    // askUser：调用方负责触发 onResumePrompt。
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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/resume_position_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/resume_position.dart test/orchestration/resume_position_test.dart
git commit -m "feat(orchestration): ResumeOrchestrator with periodic save + ended clear"
```

---

## Task 21：AutoFailoverOrchestrator

**文件**：
- 新建：`lib/src/orchestration/auto_failover.dart`
- 测试：`test/orchestration/auto_failover_test.dart`

- [ ] **步骤 1：失败测试**

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

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/orchestration/auto_failover_test.dart`
预期：失败。

- [ ] **步骤 3：实现**

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

- [ ] **步骤 4：跑测试**

执行：`flutter test test/orchestration/auto_failover_test.dart`
预期：通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/orchestration/auto_failover.dart test/orchestration/auto_failover_test.dart
git commit -m "feat(orchestration): AutoFailoverOrchestrator picks next priority line"
```

---

## Task 22：新 kernel 事件 LineSwitching / LineSwitched / LineSwitchFailed

**文件**：
- 修改：`lib/src/domain/player_state.dart`

- [ ] **步骤 1：加三个事件类**

在 `lib/src/domain/player_state.dart` 中、`BackendSelected` / `FallbackTriggered` 等 sealed class 邻近位置追加：

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

- [ ] **步骤 2：analyze 检查**

执行：`flutter analyze lib/src/domain/player_state.dart`
预期：无 issue。

- [ ] **步骤 3：提交**

```bash
git add lib/src/domain/player_state.dart
git commit -m "feat(kernel): add LineSwitching/LineSwitched/LineSwitchFailed events"
```

---

## Task 23：把 NiumaPlayerController 迁移到 NiumaMediaSource（增量）

**文件**：
- 修改：`lib/src/presentation/niuma_player_controller.dart`
- 修改：`test/state_machine_test.dart`
- 修改：`example/lib/player_page.dart`（如果它直接 new `NiumaPlayerController`）

controller 当前接受 `NiumaDataSource`。改为接受 `NiumaMediaSource`，并提供 `.dataSource(NiumaDataSource)` factory 兼容旧用法。

- [ ] **步骤 1：读当前 controller 签名**

执行：`head -70 lib/src/presentation/niuma_player_controller.dart`
注意构造函数与 `dataSource` 字段。

- [ ] **步骤 2：修改 controller**

把相关块替换为：

```dart
import '../orchestration/multi_source.dart';

// 在 class NiumaPlayerController 内：
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

/// 仅使用单 line 的调用方的兼容 getter。
NiumaDataSource get dataSource => source.currentLine.source;
```

在 `_runInitialize()` 与 `_initNative()` 中，把对 `dataSource` 的引用改为 `source.currentLine.source`（或继续用 `dataSource` getter，因为它就返回 `currentLine.source`）。

- [ ] **步骤 3：更新已有测试**

在 `test/state_machine_test.dart` 中，把所有：

```dart
NiumaPlayerController(NiumaDataSource.network(...), ...)
```

替换为：

```dart
NiumaPlayerController.dataSource(NiumaDataSource.network(...), ...)
```

执行：`flutter test test/state_machine_test.dart`
预期：通过（行为不变）。

- [ ] **步骤 4：更新 example**

如果 `example/lib/player_page.dart` 直接 new controller，改用 `.dataSource(...)` factory。

执行：`cd example && flutter analyze`
预期：无 issue。

- [ ] **步骤 5：跑全局 analyze + 测试**

执行：`flutter analyze && flutter test`
预期：全 clean / pass。

- [ ] **步骤 6：提交**

```bash
git add lib/src/presentation/niuma_player_controller.dart test/state_machine_test.dart example/lib/player_page.dart
git commit -m "refactor(kernel): controller accepts NiumaMediaSource; .dataSource factory keeps single-source ergonomics"
```

---

## Task 24：把 SourceMiddleware pipeline 接进 controller.initialize()

**文件**：
- 修改：`lib/src/presentation/niuma_player_controller.dart`
- 修改：`test/state_machine_test.dart`

- [ ] **步骤 1：失败测试**

往 `test/state_machine_test.dart` 加：

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
  // FakeBackendFactory 应记录它被构造时拿到的 source。
  expect(fake.lastSourceFromMiddleware?.headers, {'X': '1', 'Y': '2'});
  ctrl.dispose();
});
```

（在测试文件加上 `import 'package:niuma_player/src/orchestration/source_middleware.dart';` 与 `import 'package:niuma_player/src/orchestration/multi_source.dart';`。）

确保 `FakeBackendFactory` 在 `createVideoPlayer` / `createNative` 中记录收到的 `NiumaDataSource`。

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/state_machine_test.dart`
预期：失败。

- [ ] **步骤 3：实现**

在 `niuma_player_controller.dart` 中：

```dart
import '../orchestration/source_middleware.dart';

NiumaPlayerController(
  this.source, {
  this.middlewares = const [],
  // ...其它
});

final List<SourceMiddleware> middlewares;

NiumaDataSource _resolvedSource = const _PlaceholderSource();

Future<NiumaDataSource> _resolveSource() async {
  return runSourceMiddlewares(source.currentLine.source, middlewares);
}
```

修改 `_runInitialize()`：先 `_resolvedSource = await _resolveSource()`，再把 `_resolvedSource` 而不是 `dataSource` 传给 backend factory。

backend factory 的签名已经接受 `NiumaDataSource`，只需改调用点：

```dart
await _attachBackend(_backendFactory.createVideoPlayer(_resolvedSource));
// ...
await _attachBackend(_backendFactory.createNative(_resolvedSource, forceIjk: forceIjk));
```

- [ ] **步骤 4：跑测试**

执行：`flutter test`
预期：全部通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/presentation/niuma_player_controller.dart test/state_machine_test.dart
git commit -m "feat(kernel): controller runs SourceMiddleware pipeline before backend"
```

---

## Task 25：controller.switchLine(id)

**文件**：
- 修改：`lib/src/presentation/niuma_player_controller.dart`
- 修改：`test/state_machine_test.dart`

- [ ] **步骤 1：失败测试**

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

（给 `FakeBackendFactory` 加上 `simulatePosition` 与 `lastSeekTarget`。）

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/state_machine_test.dart`
预期：失败 — `switchLine` 未定义。

- [ ] **步骤 3：实现**

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

    // 根据 platform / forceIjk 策略构建对应 backend。
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

（确保 `_initNative` 不再直接读 `dataSource`，统一用 `_resolvedSource`。）

- [ ] **步骤 4：跑测试**

执行：`flutter test`
预期：全部通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/presentation/niuma_player_controller.dart test/state_machine_test.dart
git commit -m "feat(kernel): controller.switchLine with seek-restore + line events"
```

---

## Task 26：在 initialize() 失败时套用 RetryPolicy

**文件**：
- 修改：`lib/src/presentation/niuma_player_controller.dart`
- 修改：`test/state_machine_test.dart`

- [ ] **步骤 1：失败测试**

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
    platform: FakePlatformBridge(isIOS: false), // Android 路径
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
  expect(fake.nativeForceIjkArgs, hasLength(2)); // 已有的 forceIjk fallback retry
});
```

（`_Throw` / `_Succeed` 为本地 helper class，驱动 `FakeBackendFactory` 的预设响应。）

- [ ] **步骤 2：跑测试确认失败**

执行：`flutter test test/state_machine_test.dart`
预期：失败。

- [ ] **步骤 3：实现**

在 `niuma_player_controller.dart` 中：

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

把最内层的 `await native.initialize()`（或 `await _backend!.initialize()`）包进重试循环：

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
  // 已有路径：原生错误以 PlatformException 字符串形式向上传；这里
  // 按已知 signature 分类。默认返回 unknown。
  return PlayerErrorCategory.unknown;
}
```

用 `_initializeWithRetry` 包住 *单 line 尝试*（**不要**包住 Android 已有的 forceIjk Try-Fail-Remember loop —— 那一层保留）。两层并存：先 retry（transient/network），耗尽之后才走原有 forceIjk fallback。

- [ ] **步骤 4：跑测试**

执行：`flutter test`
预期：全部通过。

- [ ] **步骤 5：提交**

```bash
git add lib/src/presentation/niuma_player_controller.dart test/state_machine_test.dart
git commit -m "feat(kernel): apply RetryPolicy around backend.initialize"
```

---

## Task 27：公开导出

**文件**：
- 修改：`lib/niuma_player.dart`

- [ ] **步骤 1：加导出**

把已有的 export 替换为：

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

- [ ] **步骤 2：analyze 检查**

执行：`flutter analyze`
预期：无 issue。

- [ ] **步骤 3：提交**

```bash
git add lib/niuma_player.dart
git commit -m "feat: export M7 orchestration + observability public API"
```

---

## Task 28：更新 CHANGELOG

**文件**：
- 修改：`CHANGELOG.md`

- [ ] **步骤 1：编辑 changelog**

替换 `## [Unreleased]` 段：

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

- [ ] **步骤 2：提交**

```bash
git add CHANGELOG.md
git commit -m "docs: log M7 orchestration + observability under [Unreleased]"
```

---

## Task 29：最终自检

- [ ] **步骤 1：全量 analyze**

执行：`flutter analyze`
预期：0 issue。

- [ ] **步骤 2：全量测试**

执行：`flutter test`
预期：全部通过（kernel 14 个 + 新增 orchestration 测试）。

- [ ] **步骤 3：dartdoc dry run**

执行：`dart doc --dry-run`
预期：0 warning，0 error。

- [ ] **步骤 4：pub publish dry run**

执行：`flutter pub publish --dry-run 2>&1 | grep -B1 -A3 "^\*"`
预期：只剩无法避免的 "modified in git" warning。

- [ ] **步骤 5：构建 smoke（Android debug + Web）**

执行：
```bash
cd example
flutter build apk --debug
flutter build web
```
预期：两个都成功。

- [ ] **步骤 6：把残留的零碎修复一并提交**

```bash
git status   # 应该是干净的，或仅有过期 .lock 改动
```

如果自检过程中改了什么，用清晰的 message 提交。

---

## 自检对照

Spec 覆盖检查（章节 ↔ Task）：

| Spec 章节 | Task |
|---|---|
| 1. 架构分层 | 文件在 Task 1–21 落地，`lib/testing.dart` 在 Task 13 |
| 2. NiumaVideoPlayer 公共 API | **超出范围**（M9） |
| 3. 手势仲裁器 | **超出范围**（M8） |
| 4. 生命周期 | **超出范围**（M8） |
| 4.7 后台音频 | **超出范围**（M6） |
| 5. 广告 cue 系统 | Task 14（类型）+ 15（schedule）+ 16–19（scheduler）+ 25（analytics） |
| 6.1 多源 | Task 5 + 6 + 7（类型）+ 21（failover）+ 22（事件）+ 25（switchLine） |
| 6.2 续播 | Task 8 + 9 + 10（类型）+ 20（orchestrator） |
| 6.3 VTT 缩略图 | **超出范围**（M8） |
| 6.4 Source middleware | Task 2 + 3 + 4（实现）+ 24（接进 kernel） |
| 7.3 测试替身 | Task 8 + 12 + 13 |
| 第 9 节 范围之外 | 按设计排除 |

所有 M7 相关 spec 章节都至少有一个 Task。被标 out-of-scope 的章节按计划留给 M8/M9/M6。

占位符扫描：无。所有步骤都给出了具体代码。

类型一致性：
- `NiumaMediaSource.lineById` 在 Task 6 引入；在 Task 25 中使用 ✓
- `AdControllerImpl.dismiss` 在 Task 19 定义；AdSchedulerOrchestrator 接入挂在 Task 25-pending —— 通过 `AdSchedulerOrchestrator.fire` 接 AnalyticsEmitter（在 Task 16 已经接受 emitter；midRoll/pauseAd/postRoll 通过同一个 `_fire` 共享）。
