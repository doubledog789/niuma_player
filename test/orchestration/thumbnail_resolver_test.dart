import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/thumbnail_cache.dart';
import 'package:niuma_player/src/orchestration/thumbnail_resolver.dart';
import 'package:niuma_player/src/orchestration/thumbnail_track.dart';

void main() {
  group('ThumbnailResolver.resolve', () {
    final cues = <WebVttCue>[
      const WebVttCue(
        start: Duration.zero,
        end: Duration(seconds: 5),
        spriteUrl: 'sprite.jpg',
        region: Rect.fromLTWH(0, 0, 128, 72),
      ),
      const WebVttCue(
        start: Duration(seconds: 5),
        end: Duration(seconds: 10),
        spriteUrl: 'sprite.jpg',
        region: Rect.fromLTWH(128, 0, 128, 72),
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
        const WebVttCue(
          start: Duration.zero,
          end: Duration(seconds: 5),
          spriteUrl: 'https://other.com/abs.jpg',
          region: Rect.fromLTWH(0, 0, 128, 72),
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

    // C5: 恶意 baseUrl 不能让 resolve 抛——契约是"永远不抛"。
    test('非法 baseUrl 时返回 null 不抛（C5）', () {
      final cache = ThumbnailCache();
      // IPv6 字面量未关闭——Uri.parse 会抛 FormatException
      const badBase = 'http://[bad-ipv6';
      late final ThumbnailFrame? frame;
      expect(() {
        frame = ThumbnailResolver.resolve(
          position: Duration.zero,
          cues: cues,
          baseUrl: badBase,
          cache: cache,
        );
      }, returnsNormally);
      expect(frame, isNull);
    });
  });

  // TG2 / I3: 5+ cues 序列上的二分查找边界。半开区间 [start, end) —
  // start 命中、end 不命中、cue 之间 gap 返 null、cue 之后返 null。
  group('ThumbnailResolver._findCue (binary search edges, TG2/I3)', () {
    // 5 个 cue：0-5、5-10、15-20（10-15 是 gap）、20-25、30-35（25-30 又是 gap）。
    // 故意用非连续 cue 模拟 sparse VTT track。
    final cues = <WebVttCue>[
      const WebVttCue(
        start: Duration.zero,
        end: Duration(seconds: 5),
        spriteUrl: 's.jpg',
        region: Rect.fromLTWH(0, 0, 128, 72),
      ),
      const WebVttCue(
        start: Duration(seconds: 5),
        end: Duration(seconds: 10),
        spriteUrl: 's.jpg',
        region: Rect.fromLTWH(128, 0, 128, 72),
      ),
      const WebVttCue(
        start: Duration(seconds: 15),
        end: Duration(seconds: 20),
        spriteUrl: 's.jpg',
        region: Rect.fromLTWH(256, 0, 128, 72),
      ),
      const WebVttCue(
        start: Duration(seconds: 20),
        end: Duration(seconds: 25),
        spriteUrl: 's.jpg',
        region: Rect.fromLTWH(384, 0, 128, 72),
      ),
      const WebVttCue(
        start: Duration(seconds: 30),
        end: Duration(seconds: 35),
        spriteUrl: 's.jpg',
        region: Rect.fromLTWH(512, 0, 128, 72),
      ),
    ];

    ThumbnailFrame? at(int seconds) => ThumbnailResolver.resolve(
          position: Duration(seconds: seconds),
          cues: cues,
          baseUrl: 'https://cdn.com/v.vtt',
          cache: ThumbnailCache(),
        );

    test('命中第一个 cue 的中段', () {
      expect(at(2)!.region.left, 0);
    });

    test('命中中间 cue', () {
      expect(at(17)!.region.left, 256);
    });

    test('命中最后一个 cue', () {
      expect(at(33)!.region.left, 512);
    });

    test('position == cue.start 命中（半开区间含起点）', () {
      expect(at(15)!.region.left, 256);
      expect(at(20)!.region.left, 384);
      expect(at(0)!.region.left, 0);
    });

    test('position == cue.end 不命中（半开区间不含终点）', () {
      // 5 是 cue[0].end 但也是 cue[1].start → 走到 cue[1]
      expect(at(5)!.region.left, 128);
      // 10 是 cue[1].end，cue[2] 从 15 才开始 → null
      expect(at(10), isNull);
      // 25 是 cue[3].end，cue[4] 从 30 开始 → null
      expect(at(25), isNull);
      // 35 是 cue[4].end，没下一 cue → null
      expect(at(35), isNull);
    });

    test('两个 cue 之间的 gap 返 null', () {
      // cue[1] 5-10 与 cue[2] 15-20 之间，position=12 落在 gap 内
      expect(at(12), isNull);
      // cue[3] 20-25 与 cue[4] 30-35 之间
      expect(at(27), isNull);
    });

    test('500+ cues perf smoke：1000 次 resolve < 100ms', () {
      // 填 500 个连续 cue，每个 1 秒
      final big = List<WebVttCue>.generate(
        500,
        (i) => WebVttCue(
          start: Duration(seconds: i),
          end: Duration(seconds: i + 1),
          spriteUrl: 'sprite${i ~/ 100}.jpg',
          region: Rect.fromLTWH((i % 100).toDouble() * 128, 0, 128, 72),
        ),
      );
      final cache = ThumbnailCache();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        ThumbnailResolver.resolve(
          position: Duration(milliseconds: (i * 471) % 500000),
          cues: big,
          baseUrl: 'https://cdn.com/v.vtt',
          cache: cache,
        );
      }
      sw.stop();
      // 二分查找下，1000 次 × log2(500) ≈ 9000 次比较，远低于 100ms。
      // 这里给宽松上限，主要是防止有人不小心改回 O(n)。
      expect(sw.elapsedMilliseconds, lessThan(100),
          reason: 'binary search regressed to linear?');
    });
  });
}
