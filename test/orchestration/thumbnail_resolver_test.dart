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
}
