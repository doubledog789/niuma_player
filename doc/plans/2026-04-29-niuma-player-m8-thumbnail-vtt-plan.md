# M8 — 缩略图 VTT 实施计划

> **执行方式**：用 `superpowers:subagent-driven-development` 跑这份计划。任务用 `- [ ]` 复选框标注。

**目标**：给 `NiumaMediaSource` 加 WebVTT thumbnail track 支持。Controller 能根据时间位置返回 sprite 图引用 + 裁剪矩形。M8 是**纯数据 / 逻辑层**，不含 UI 组件（UI 留 M9）。

**架构**：
- VTT 解析（pure Dart，只支持 thumbnail 变种）
- Sprite 图缓存（按 URL 去重 + LRU 上限）
- `NiumaMediaSource.thumbnailVtt` 可选字段
- `controller.thumbnailFor(Duration)` 公共 API
- 复用 M7 `SourceMiddleware`（VTT URL 也走签名 / header 流水线）

**技术栈**：纯 Dart，依赖现有 `package:flutter` `ImageProvider` + `NetworkImage`。`http` 走 `flutter` 自带 `dart:io HttpClient`，无新增第三方依赖。

---

## 文件结构

**新增**：

| 文件 | 职责 |
|---|---|
| `lib/src/orchestration/webvtt_parser.dart` | VTT 文本 → `List<WebVttCue>`；只解析 thumbnail 变种 |
| `lib/src/orchestration/thumbnail_track.dart` | `ThumbnailFrame` / `WebVttCue` 数据类 |
| `lib/src/orchestration/thumbnail_cache.dart` | sprite URL → `ImageProvider` 去重缓存 + LRU |
| `lib/src/orchestration/thumbnail_resolver.dart` | 把 `(Duration, cues, cache)` 组装成 `ThumbnailFrame?`；含 fetch VTT 的逻辑 |
| `test/orchestration/webvtt_parser_test.dart` | parser 单测 |
| `test/orchestration/thumbnail_cache_test.dart` | cache LRU 单测 |
| `test/orchestration/thumbnail_resolver_test.dart` | resolver 单测（含 cue 边界查找） |

**修改**：

| 文件 | 改动 |
|---|---|
| `lib/src/orchestration/multi_source.dart` | `NiumaMediaSource` 加 `String? thumbnailVtt` 字段（两个 factory 都加） |
| `lib/src/presentation/niuma_player_controller.dart` | 启动时若有 `thumbnailVtt` 走 middleware → fetch VTT → 解析；加 `thumbnailFor(Duration)` 方法；dispose 清缓存 |
| `lib/niuma_player.dart` | 导出 `ThumbnailFrame`、`WebVttCue`（其他保持内部） |
| `README.md` | 加 "M8 features" 章节（中文） |
| `CHANGELOG.md` | `[Unreleased]` → M8 added 段（中文） |
| `pubspec.yaml` | bump 0.2.0 → 0.3.0（任务 10 收口时做） |

---

## 任务清单

### Task 1：WebVTT parser（thumbnail 变种）

**文件**：
- 新建：`lib/src/orchestration/thumbnail_track.dart`、`lib/src/orchestration/webvtt_parser.dart`
- 测试：`test/orchestration/webvtt_parser_test.dart`

参考输入（artplayer 提供的真实样例）：
```
WEBVTT

00:00.000 --> 00:05.000
bbb-sprite.jpg#xywh=0,0,128,72

00:05.000 --> 00:10.000
bbb-sprite.jpg#xywh=128,0,128,72
```

也要支持 `HH:MM:SS.mmm` 格式（长视频会用到）和 cue 之间的空行变体。

- [ ] **步骤 1.1**：先写数据类 `lib/src/orchestration/thumbnail_track.dart`：

```dart
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ImageProvider;

/// 一条 WebVTT thumbnail cue：起止时间 + sprite URL + 裁剪矩形。
@immutable
class WebVttCue {
  const WebVttCue({
    required this.start,
    required this.end,
    required this.spriteUrl,
    required this.region,
  });

  final Duration start;
  final Duration end;
  final String spriteUrl;
  final Rect region;

  bool contains(Duration position) =>
      position >= start && position < end;

  @override
  bool operator ==(Object other) =>
      other is WebVttCue &&
      start == other.start &&
      end == other.end &&
      spriteUrl == other.spriteUrl &&
      region == other.region;

  @override
  int get hashCode => Object.hash(start, end, spriteUrl, region);
}

/// `controller.thumbnailFor(...)` 的返回值：图片提供者 + 在原图里的裁剪矩形。
@immutable
class ThumbnailFrame {
  const ThumbnailFrame({required this.image, required this.region});

  final ImageProvider image;
  final Rect region;
}
```

- [ ] **步骤 1.2**：先写失败的 parser 测试 `test/orchestration/webvtt_parser_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/webvtt_parser.dart';

void main() {
  group('WebVttParser.parseThumbnails', () {
    test('解析 MM:SS.mmm 格式的 cue', () {
      const input = '''
WEBVTT

00:00.000 --> 00:05.000
bbb-sprite.jpg#xywh=0,0,128,72

00:05.000 --> 00:10.000
bbb-sprite.jpg#xywh=128,0,128,72
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 2);
      expect(cues[0].start, Duration.zero);
      expect(cues[0].end, const Duration(seconds: 5));
      expect(cues[0].spriteUrl, 'bbb-sprite.jpg');
      expect(cues[0].region.left, 0);
      expect(cues[0].region.top, 0);
      expect(cues[0].region.width, 128);
      expect(cues[0].region.height, 72);
    });

    test('解析 HH:MM:SS.mmm 格式（长视频）', () {
      const input = '''
WEBVTT

01:23:45.000 --> 01:23:50.000
sprite.jpg#xywh=0,0,160,90
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
      expect(cues[0].start, const Duration(hours: 1, minutes: 23, seconds: 45));
    });

    test('忽略坏的 cue，保留好的', () {
      const input = '''
WEBVTT

00:00.000 --> 00:05.000
sprite.jpg#xywh=BAD

00:05.000 --> 00:10.000
sprite.jpg#xywh=128,0,128,72
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
      expect(cues[0].region.left, 128);
    });

    test('缺 WEBVTT 头时抛 FormatException', () {
      expect(() => WebVttParser.parseThumbnails('00:00.000 --> 00:05.000'),
          throwsFormatException);
    });

    test('空文件返回空列表', () {
      final cues = WebVttParser.parseThumbnails('WEBVTT\n');
      expect(cues, isEmpty);
    });

    test('解析多张 sprite 引用（长视频常见）', () {
      const input = '''
WEBVTT

00:00.000 --> 00:05.000
sprite-1.jpg#xywh=0,0,128,72

00:05.000 --> 00:10.000
sprite-2.jpg#xywh=0,0,128,72
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.map((c) => c.spriteUrl).toSet(),
          {'sprite-1.jpg', 'sprite-2.jpg'});
    });
  });
}
```

- [ ] **步骤 1.3**：跑测试确认全失败：

```
flutter test test/orchestration/webvtt_parser_test.dart
预期：FAIL（WebVttParser 未定义）
```

- [ ] **步骤 1.4**：实现 parser `lib/src/orchestration/webvtt_parser.dart`：

```dart
import 'dart:ui' show Rect;

import 'thumbnail_track.dart';

/// WebVTT 解析器（thumbnail 变种）。
///
/// 只识别形如 `bbb-sprite.jpg#xywh=0,0,128,72` 的 cue 内容。
/// 字幕变种（cue body 是文本）暂不支持。
abstract class WebVttParser {
  WebVttParser._();

  /// 解析 [input] 并返回所有 cue。
  ///
  /// - 输入必须以 `WEBVTT` 开头（大小写敏感，按 RFC 8216 §4.5）。
  /// - 单条 cue 出错（时间码 / xywh 无法解析）会被跳过，不影响其它 cue。
  /// - 返回结果按 [WebVttCue.start] 升序。
  static List<WebVttCue> parseThumbnails(String input) {
    final lines = input.split(RegExp(r'\r?\n'));
    if (lines.isEmpty || !lines.first.trim().startsWith('WEBVTT')) {
      throw const FormatException('输入不是合法的 WebVTT（缺 "WEBVTT" 头）');
    }

    final cues = <WebVttCue>[];
    var i = 1;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty || !line.contains('-->')) {
        i++;
        continue;
      }
      // 这是 cue 时间行；下一个非空行是 cue 内容。
      final times = _parseTimes(line);
      if (times == null) {
        i++;
        continue;
      }
      i++;
      while (i < lines.length && lines[i].trim().isEmpty) {
        i++;
      }
      if (i >= lines.length) break;
      final body = lines[i].trim();
      final cue = _parseSpriteRef(body, times.$1, times.$2);
      if (cue != null) cues.add(cue);
      i++;
    }
    return cues;
  }

  static (Duration, Duration)? _parseTimes(String line) {
    final m = RegExp(
      r'^((?:\d{2}:)?\d{2}:\d{2}\.\d{3})\s*-->\s*((?:\d{2}:)?\d{2}:\d{2}\.\d{3})',
    ).firstMatch(line);
    if (m == null) return null;
    final start = _parseTimestamp(m.group(1)!);
    final end = _parseTimestamp(m.group(2)!);
    if (start == null || end == null) return null;
    return (start, end);
  }

  static Duration? _parseTimestamp(String s) {
    final parts = s.split(':');
    try {
      int hours = 0, minutes, seconds, ms;
      if (parts.length == 3) {
        hours = int.parse(parts[0]);
        minutes = int.parse(parts[1]);
        final secMs = parts[2].split('.');
        seconds = int.parse(secMs[0]);
        ms = int.parse(secMs[1]);
      } else {
        minutes = int.parse(parts[0]);
        final secMs = parts[1].split('.');
        seconds = int.parse(secMs[0]);
        ms = int.parse(secMs[1]);
      }
      return Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        milliseconds: ms,
      );
    } catch (_) {
      return null;
    }
  }

  static WebVttCue? _parseSpriteRef(String body, Duration start, Duration end) {
    final hashIdx = body.indexOf('#xywh=');
    if (hashIdx < 0) return null;
    final spriteUrl = body.substring(0, hashIdx);
    final coords = body.substring(hashIdx + 6).split(',');
    if (coords.length != 4) return null;
    try {
      final x = int.parse(coords[0]).toDouble();
      final y = int.parse(coords[1]).toDouble();
      final w = int.parse(coords[2]).toDouble();
      final h = int.parse(coords[3]).toDouble();
      return WebVttCue(
        start: start,
        end: end,
        spriteUrl: spriteUrl,
        region: Rect.fromLTWH(x, y, w, h),
      );
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **步骤 1.5**：跑测试确认全过：

```
flutter test test/orchestration/webvtt_parser_test.dart
预期：6/6 PASS
flutter analyze
预期：No issues
```

- [ ] **步骤 1.6**：commit：

```
git add lib/src/orchestration/thumbnail_track.dart lib/src/orchestration/webvtt_parser.dart test/orchestration/webvtt_parser_test.dart
git commit -m "feat(m8): WebVTT thumbnail parser + ThumbnailFrame data types

支持 MM:SS.mmm 和 HH:MM:SS.mmm 时间格式，以及 'sprite.jpg#xywh=x,y,w,h'
sprite 引用语法。单个 cue 解析失败会被跳过，不影响整体。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2：Thumbnail cache（sprite 图去重 + LRU）

**文件**：
- 新建：`lib/src/orchestration/thumbnail_cache.dart`
- 测试：`test/orchestration/thumbnail_cache_test.dart`

VTT 通常引用一张大 sprite 图（包含所有缩略图），但长视频可能引用多张。Cache 按 URL 去重，单个 source 最多缓存 N 张（可配置），超过 N 张时按 LRU 淘汰。

- [ ] **步骤 2.1**：失败测试：

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/thumbnail_cache.dart';

void main() {
  group('ThumbnailCache', () {
    test('同一 URL 返回同一个 ImageProvider 实例（去重）', () {
      final cache = ThumbnailCache();
      final a = cache.getOrCreate('https://x/sprite.jpg');
      final b = cache.getOrCreate('https://x/sprite.jpg');
      expect(identical(a, b), isTrue);
    });

    test('不同 URL 返回不同实例', () {
      final cache = ThumbnailCache();
      final a = cache.getOrCreate('https://x/a.jpg');
      final b = cache.getOrCreate('https://x/b.jpg');
      expect(identical(a, b), isFalse);
    });

    test('超过容量时淘汰最久未访问的', () {
      final cache = ThumbnailCache(maxEntries: 2);
      final a = cache.getOrCreate('a.jpg');
      cache.getOrCreate('b.jpg');
      cache.getOrCreate('a.jpg'); // a 重新被访问
      cache.getOrCreate('c.jpg'); // 应该把 b 挤掉
      expect(cache.contains('a.jpg'), isTrue);
      expect(cache.contains('b.jpg'), isFalse);
      expect(cache.contains('c.jpg'), isTrue);
      // a 实例还是同一个
      expect(identical(cache.getOrCreate('a.jpg'), a), isTrue);
    });

    test('clear() 清空全部', () {
      final cache = ThumbnailCache();
      cache.getOrCreate('a.jpg');
      cache.clear();
      expect(cache.contains('a.jpg'), isFalse);
    });
  });
}
```

- [ ] **步骤 2.2**：跑测试确认失败。

- [ ] **步骤 2.3**：实现：

```dart
import 'dart:collection';

import 'package:flutter/widgets.dart' show ImageProvider, NetworkImage;

/// 按 sprite URL 去重的 ImageProvider 缓存，支持 LRU 上限。
///
/// 同一 [NiumaPlayerController] 生命周期内复用；dispose 时清空。
class ThumbnailCache {
  ThumbnailCache({this.maxEntries = 8});

  /// 单个 source 同时缓存的最大 sprite 数。短视频通常 1 张就够，
  /// 长视频按 100 张缩略图 / sprite 估，[maxEntries=8] 能覆盖 800 帧。
  final int maxEntries;

  // LinkedHashMap 保留插入顺序，便于实现 LRU。
  final LinkedHashMap<String, ImageProvider> _entries =
      LinkedHashMap<String, ImageProvider>();

  /// 拿 [url] 对应的 [ImageProvider]，没有则新建（默认 [NetworkImage]）。
  /// 访问会更新 LRU 顺序。
  ImageProvider getOrCreate(String url) {
    final existing = _entries.remove(url);
    if (existing != null) {
      _entries[url] = existing; // 重新插到最新位置
      return existing;
    }
    final provider = NetworkImage(url);
    _entries[url] = provider;
    if (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first); // 淘汰最旧的
    }
    return provider;
  }

  bool contains(String url) => _entries.containsKey(url);

  void clear() => _entries.clear();
}
```

- [ ] **步骤 2.4**：跑测试 PASS + analyze 干净。

- [ ] **步骤 2.5**：commit：

```
git add lib/src/orchestration/thumbnail_cache.dart test/orchestration/thumbnail_cache_test.dart
git commit -m "feat(m8): ThumbnailCache with URL dedup + LRU eviction

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 3：Thumbnail resolver（cue 查找 + sprite URL 解析）

**文件**：
- 新建：`lib/src/orchestration/thumbnail_resolver.dart`
- 测试：`test/orchestration/thumbnail_resolver_test.dart`

把 `(position, cues, cache)` 解析成 `ThumbnailFrame`。需要处理 sprite URL 的相对路径（cue 写 `sprite.jpg`，但 VTT 文件本身在 `https://cdn.com/x/thumbs.vtt`，相对路径要解析成 `https://cdn.com/x/sprite.jpg`）。

- [ ] **步骤 3.1**：失败测试：

```dart
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/thumbnail_cache.dart';
import 'package:niuma_player/src/orchestration/thumbnail_resolver.dart';
import 'package:niuma_player/src/orchestration/thumbnail_track.dart';

void main() {
  group('ThumbnailResolver.resolve', () {
    final cues = <WebVttCue>[
      WebVttCue(
        start: Duration.zero,
        end: const Duration(seconds: 5),
        spriteUrl: 'sprite.jpg',
        region: const Rect.fromLTWH(0, 0, 128, 72),
      ),
      WebVttCue(
        start: const Duration(seconds: 5),
        end: const Duration(seconds: 10),
        spriteUrl: 'sprite.jpg',
        region: const Rect.fromLTWH(128, 0, 128, 72),
      ),
    ];

    test('返回包含该 position 的 cue 对应 frame', () {
      final cache = ThumbnailCache();
      final frame = ThumbnailResolver.resolve(
        position: const Duration(seconds: 3),
        cues: cues,
        baseUrl: 'https://cdn.com/x/thumbs.vtt',
        cache: cache,
      );
      expect(frame, isNotNull);
      expect(frame!.region.left, 0);
    });

    test('position 在最后 cue 之后返回 null', () {
      final cache = ThumbnailCache();
      final frame = ThumbnailResolver.resolve(
        position: const Duration(seconds: 99),
        cues: cues,
        baseUrl: 'https://cdn.com/x/thumbs.vtt',
        cache: cache,
      );
      expect(frame, isNull);
    });

    test('相对 sprite URL 用 baseUrl 解析为绝对', () {
      final cache = ThumbnailCache();
      ThumbnailResolver.resolve(
        position: Duration.zero,
        cues: cues,
        baseUrl: 'https://cdn.com/x/thumbs.vtt',
        cache: cache,
      );
      expect(cache.contains('https://cdn.com/x/sprite.jpg'), isTrue);
    });

    test('绝对 sprite URL 不被改写', () {
      final absCues = [
        WebVttCue(
          start: Duration.zero,
          end: const Duration(seconds: 5),
          spriteUrl: 'https://other.com/abs.jpg',
          region: const Rect.fromLTWH(0, 0, 128, 72),
        ),
      ];
      final cache = ThumbnailCache();
      ThumbnailResolver.resolve(
        position: Duration.zero,
        cues: absCues,
        baseUrl: 'https://cdn.com/x/thumbs.vtt',
        cache: cache,
      );
      expect(cache.contains('https://other.com/abs.jpg'), isTrue);
    });

    test('空 cue 列表返回 null', () {
      final cache = ThumbnailCache();
      final frame = ThumbnailResolver.resolve(
        position: Duration.zero,
        cues: const <WebVttCue>[],
        baseUrl: 'https://x.com/v.vtt',
        cache: cache,
      );
      expect(frame, isNull);
    });
  });
}
```

- [ ] **步骤 3.2**：跑测试失败。

- [ ] **步骤 3.3**：实现：

```dart
import 'thumbnail_cache.dart';
import 'thumbnail_track.dart';

/// 把 [position] 映射成 [ThumbnailFrame]：在 [cues] 里找包含 position 的那条，
/// 用 [baseUrl] 解析相对 sprite URL，从 [cache] 拿对应 ImageProvider。
abstract class ThumbnailResolver {
  ThumbnailResolver._();

  /// 找到包含 [position] 的 cue 并返回 frame；如果没有 cue 命中返回 null。
  static ThumbnailFrame? resolve({
    required Duration position,
    required List<WebVttCue> cues,
    required String baseUrl,
    required ThumbnailCache cache,
  }) {
    if (cues.isEmpty) return null;
    final cue = _findCue(cues, position);
    if (cue == null) return null;
    final absoluteUrl = _resolveSpriteUrl(cue.spriteUrl, baseUrl);
    return ThumbnailFrame(
      image: cache.getOrCreate(absoluteUrl),
      region: cue.region,
    );
  }

  static WebVttCue? _findCue(List<WebVttCue> cues, Duration position) {
    // cues 按 start 升序。线性扫描足够（cue 数量 typical 几十~几百）。
    // 后续若需优化可改成二分。
    for (final cue in cues) {
      if (cue.contains(position)) return cue;
    }
    return null;
  }

  static String _resolveSpriteUrl(String spriteUrl, String baseUrl) {
    if (spriteUrl.startsWith('http://') || spriteUrl.startsWith('https://')) {
      return spriteUrl;
    }
    final base = Uri.parse(baseUrl);
    return base.resolve(spriteUrl).toString();
  }
}
```

- [ ] **步骤 3.4**：跑测试 PASS + analyze 干净。

- [ ] **步骤 3.5**：commit：

```
git add lib/src/orchestration/thumbnail_resolver.dart test/orchestration/thumbnail_resolver_test.dart
git commit -m "feat(m8): ThumbnailResolver maps Duration to ThumbnailFrame

包含相对 sprite URL 解析（按 VTT 文件 baseUrl 拼绝对路径）。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4：NiumaMediaSource 加 `thumbnailVtt` 字段

**文件**：
- 修改：`lib/src/orchestration/multi_source.dart`
- 测试：`test/orchestration/multi_source_test.dart`（追加测试）

- [ ] **步骤 4.1**：先扩展现有测试，加两条：

```dart
test('NiumaMediaSource.single 带 thumbnailVtt 时正确暴露', () {
  final ds = NiumaDataSource.network('https://x/v.mp4');
  final src = NiumaMediaSource.single(
    ds,
    thumbnailVtt: 'https://x/thumbs.vtt',
  );
  expect(src.thumbnailVtt, 'https://x/thumbs.vtt');
});

test('NiumaMediaSource.lines 不传 thumbnailVtt 时为 null', () {
  final src = NiumaMediaSource.lines(
    lines: [MediaLine(id: 'a', source: NiumaDataSource.network('x'))],
    defaultLineId: 'a',
  );
  expect(src.thumbnailVtt, isNull);
});
```

- [ ] **步骤 4.2**：跑测试失败（属性不存在）。

- [ ] **步骤 4.3**：在 `multi_source.dart` 改：

```dart
class NiumaMediaSource {
  const NiumaMediaSource._({
    required this.lines,
    required this.defaultLineId,
    this.thumbnailVtt,        // 新增
  });

  factory NiumaMediaSource.single(
    NiumaDataSource source, {
    String? thumbnailVtt,   // 新增
  }) { ... }

  factory NiumaMediaSource.lines({
    required List<MediaLine> lines,
    required String defaultLineId,
    String? thumbnailVtt,   // 新增
  }) { ... }

  ...

  /// 可选的 WebVTT 缩略图轨道 URL（[thumbnailVtt] 是 null 表示不启用缩略图功能）。
  /// 不区分清晰度——thumbnail 是内容属性，所有 [lines] 共享一份。
  final String? thumbnailVtt;
}
```

记得 dartdoc。

- [ ] **步骤 4.4**：跑测试 PASS + analyze。

- [ ] **步骤 4.5**：commit：

```
git add lib/src/orchestration/multi_source.dart test/orchestration/multi_source_test.dart
git commit -m "feat(m8): NiumaMediaSource.thumbnailVtt optional URL

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 5：Controller 集成 + `thumbnailFor` 公共 API

**文件**：
- 修改：`lib/src/presentation/niuma_player_controller.dart`
- 测试：`test/state_machine_test.dart`（加 group "thumbnailFor"）

实现要点：
- `_runInitialize` 末尾若 `source.thumbnailVtt != null`：
  - 走 `runSourceMiddlewares` 把 VTT URL 包成 `NiumaDataSource.network(thumbnailVtt)` 跑一遍（拿到签名后的 URL + headers）
  - HTTP fetch（用 `dart:io HttpClient`，因为 niuma_player 已经是 platform-aware 的，web 这条路 fetch 用 `package:http`？或者干脆挂依赖）

  **简化决策**：M8 这版只支持网络 URL。fetch 用 `package:http`（pubspec 加这个依赖）。Web 上用 `package:http` 自动走 `XMLHttpRequest`，跨平台一致。
- 解析失败 / fetch 失败：**不抛**，只 log + 设置内部 `_thumbnailCues = const []`。`thumbnailFor` 返回 null。视频播放完全不受影响。
- `thumbnailFor(Duration position) → ThumbnailFrame?` 公共方法。
- `dispose()` 里清 cache。

- [ ] **步骤 5.1**：先在 `pubspec.yaml` 加 `http: ^1.0.0` 依赖（在 `dependencies:` 块）。

- [ ] **步骤 5.2**：失败测试（在 `test/state_machine_test.dart` 加 group）：

```dart
group('thumbnailFor', () {
  test('source.thumbnailVtt 为 null 时返回 null', () async {
    final c = NiumaPlayerController.dataSource(
      NiumaDataSource.network('https://x/v.mp4'),
      backendFactory: FakeBackendFactory(...),
    );
    await c.initialize();
    expect(c.thumbnailFor(const Duration(seconds: 3)), isNull);
    await c.dispose();
  });

  test('VTT fetch 失败时 thumbnailFor 返回 null（不影响播放）', () async {
    // 用 mock http client 模拟 fetch 失败
    // ... 具体方式见实现，可能要把 fetch 函数注入成 controller 参数
  });

  test('成功 fetch + 解析后能查出对应 frame', () async {
    // mock http client 返回固定 VTT 内容
    // ...
  });
});
```

> **实现备注（给 implementer）**：为了让 fetch 可测，在 `NiumaPlayerController` 构造器加可选参数 `Future<String> Function(Uri uri, Map<String, String> headers)? thumbnailFetcher`，默认用 `http.get`。测试时注入 fake fetcher。

- [ ] **步骤 5.3**：跑测试失败。

- [ ] **步骤 5.4**：实现 controller 改动。新增私有字段：

```dart
final ThumbnailCache _thumbnailCache = ThumbnailCache();
List<WebVttCue> _thumbnailCues = const <WebVttCue>[];
String? _resolvedThumbnailUrl; // middleware 处理过的 URL
final Future<String> Function(Uri uri, Map<String, String> headers)
    _thumbnailFetcher;
```

`_runInitialize` 末尾（成功后）异步加载 thumbnail（不 await，让播放先开起来）：

```dart
unawaited(_loadThumbnailsIfAny());

Future<void> _loadThumbnailsIfAny() async {
  final url = source.thumbnailVtt;
  if (url == null) return;
  try {
    final ds = await runSourceMiddlewares(
      NiumaDataSource.network(url),
      middlewares,
    );
    _resolvedThumbnailUrl = ds.uri;
    final body = await _thumbnailFetcher(Uri.parse(ds.uri), ds.headers);
    if (_disposed) return;
    _thumbnailCues = WebVttParser.parseThumbnails(body);
  } catch (e) {
    debugPrint('[niuma_player] thumbnail VTT 加载失败：$e（不影响播放）');
    _thumbnailCues = const <WebVttCue>[];
  }
}

ThumbnailFrame? thumbnailFor(Duration position) {
  if (_thumbnailCues.isEmpty || _resolvedThumbnailUrl == null) return null;
  return ThumbnailResolver.resolve(
    position: position,
    cues: _thumbnailCues,
    baseUrl: _resolvedThumbnailUrl!,
    cache: _thumbnailCache,
  );
}
```

`dispose()` 加：`_thumbnailCache.clear();`

- [ ] **步骤 5.5**：跑测试 PASS + analyze 干净。

- [ ] **步骤 5.6**：commit：

```
git add -A lib/src/presentation/niuma_player_controller.dart test/state_machine_test.dart pubspec.yaml pubspec.lock
git commit -m "feat(m8): controller.thumbnailFor() with VTT fetch + cache

启动时若 source.thumbnailVtt 非 null，异步走 SourceMiddleware → fetch
→ 解析。失败不抛，只 log，视频播放不受影响。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 6：导出公共 API

**文件**：`lib/niuma_player.dart`

- [ ] **步骤 6.1**：在 `// orchestration` 段加：

```dart
export 'src/orchestration/thumbnail_track.dart' show ThumbnailFrame, WebVttCue;
```

`ThumbnailCache` / `WebVttParser` / `ThumbnailResolver` 不导出（实现细节）。

- [ ] **步骤 6.2**：跑 `flutter analyze` + `flutter test` 全绿。

- [ ] **步骤 6.3**：commit：

```
git add lib/niuma_player.dart
git commit -m "feat(m8): export ThumbnailFrame + WebVttCue public API

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 7：README + CHANGELOG 中文化记录

**文件**：`README.md`、`CHANGELOG.md`、`pubspec.yaml`

- [ ] **步骤 7.1**：`README.md` 加新章节（紧跟 "M7 features" 之后），约 25 行：

```markdown
## M8 features (缩略图 VTT)

支持 WebVTT thumbnail track，让你给进度条悬浮预览图层取数。

```dart
final controller = NiumaPlayerController.dataSource(
  NiumaDataSource.network('https://cdn.com/video.mp4'),
  thumbnailVtt: 'https://cdn.com/thumbnails.vtt',
);
await controller.initialize();

// 在进度条 hover 时调用
final frame = controller.thumbnailFor(Duration(seconds: 30));
if (frame != null) {
  // frame.image 是 ImageProvider，frame.region 是 sprite 内裁剪 rect
  // 用 RawImage / Image + custom paint 渲染即可
}
```

支持的 VTT 格式（thumbnail 变种）：

```
WEBVTT

00:00.000 --> 00:05.000
sprite.jpg#xywh=0,0,128,72
```

特性：
- 自动 fetch + 解析；失败静默降级（视频不受影响）
- Sprite 图按 URL 去重 + LRU（默认 8 张上限）
- VTT URL 同样走 `SourceMiddleware`（HeaderInjection / SignedUrl）
- 不提供 UI 组件 —— 数据层为 M9 overlay 准备
```

- [ ] **步骤 7.2**：`README.md` Roadmap 段更新：

```diff
- - **M8** — Tracks: WebVTT subtitle tracks (multi-language) + thumbnail-VTT scrub preview (sprite-based)
+ - **M8** ✅ — 缩略图 VTT scrub preview（sprite 解析 + ImageProvider 暴露）
+ - **M9** — UI overlay：fullscreen / picture-in-picture / 自定义控件 / 广告 overlay / 缩略图 hover 组件
+ - **Backlog** — 字幕 track 选择（WebVTT 多语言字幕 + sidecar / HLS 内嵌都支持）
```

- [ ] **步骤 7.3**：`CHANGELOG.md` 在 `[Unreleased]` 段加：

```markdown
## [Unreleased]

### Added (M8 — 缩略图 VTT)
- `NiumaMediaSource.thumbnailVtt` 可选字段，传入 WebVTT thumbnail track URL。
- `controller.thumbnailFor(Duration position) → ThumbnailFrame?` —— 按播放位置查
  对应缩略图（sprite 图引用 + 裁剪矩形）。
- 内置 `WebVttParser.parseThumbnails`：支持 MM:SS.mmm / HH:MM:SS.mmm 时间格式
  和 `sprite.jpg#xywh=x,y,w,h` 引用语法；单条 cue 解析失败会跳过不影响整体。
- `ThumbnailCache`：sprite URL 去重 + LRU 淘汰（默认 8 张上限）。
- 公共类型导出：`ThumbnailFrame`、`WebVttCue`（其他实现细节内部化）。
- VTT URL 走 `SourceMiddleware` 流水线（跟视频 URL 同样的签名 / header 规则）。
- VTT 加载失败静默降级：不抛异常，只 log 一条，`thumbnailFor` 返回 null，
  视频播放完全不受影响。
```

- [ ] **步骤 7.4**：`pubspec.yaml` 版本号 0.2.0 → 0.3.0。

- [ ] **步骤 7.5**：commit：

```
git add README.md CHANGELOG.md pubspec.yaml
git commit -m "docs(m8): README + CHANGELOG + version bump 0.2.0 → 0.3.0

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 8：Final sanity

- [ ] `flutter analyze` 0 issues
- [ ] `flutter test` 全绿
- [ ] `dart doc --dry-run` 0 warnings
- [ ] `flutter build web` 成功
- [ ] 所有 commit message 中文（任务 7）或英文（任务 1-6 因为面向 OSS commit log 习惯保留英文）—— 这是约定的，符合用户偏好（用户面向文档中文，但 commit log 跟 dartdoc 一样保留英文）
- [ ] 报告：commit SHA 序列、test 数量增量、文件 diff stat

---

## 风险点 / 备注

1. **`http` 包跨平台**：`package:http` 1.x 在 web 上自动走 `XMLHttpRequest`，跨域 VTT 需要 CORS 头（这是 OSS 用户自己保证的，文档里提一句）。
2. **VTT 大文件**：长视频（几小时）的 VTT 可能上千条 cue。`_findCue` 现在是 O(n) 线性扫描，每秒拖动几次进度条 cost 可接受（n=1000 仍然 < 1ms）；如果未来用户报性能问题再优化成二分。
3. **Sprite 图首次下载 lag**：用户拖到从未到过的位置可能命中刚下载的 sprite，第一帧会延迟。可以在 README 提一下"首次拖动到该 sprite 时有 100-500ms 加载延迟"。
4. **不支持本地 / asset VTT**：M8 这版只支持 `http://` / `https://`。`asset://` 之类后续可加。
