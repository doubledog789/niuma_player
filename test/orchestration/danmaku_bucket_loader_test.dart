import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/danmaku_bucket_loader.dart';
import 'package:niuma_player/src/orchestration/danmaku_models.dart';

void main() {
  group('DanmakuBucketLoader', () {
    test('loader 为 null 时 ensureLoaded 返回空列表', () async {
      final l = DanmakuBucketLoader(loader: null, bucketSize: const Duration(seconds: 60));
      final r = await l.ensureLoaded(const Duration(seconds: 30));
      expect(r, isEmpty);
    });

    test('首次进入桶触发 loader', () async {
      final calls = <(Duration, Duration)>[];
      final l = DanmakuBucketLoader(
        loader: (s, e) {
          calls.add((s, e));
          return <DanmakuItem>[
            DanmakuItem(position: s, text: 'a'),
          ];
        },
        bucketSize: const Duration(seconds: 60),
      );
      final r = await l.ensureLoaded(const Duration(seconds: 30));
      expect(calls, hasLength(1));
      expect(calls.first.$1, Duration.zero);
      expect(calls.first.$2, const Duration(seconds: 60));
      expect(r, hasLength(1));
    });

    test('同一桶内并发 ensureLoaded 共享 future（dedup）', () async {
      var callCount = 0;
      final l = DanmakuBucketLoader(
        loader: (s, e) async {
          callCount++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return [DanmakuItem(position: s, text: 't')];
        },
        bucketSize: const Duration(seconds: 60),
      );
      await Future.wait([
        l.ensureLoaded(const Duration(seconds: 10)),
        l.ensureLoaded(const Duration(seconds: 30)),
        l.ensureLoaded(const Duration(seconds: 50)),
      ]);
      expect(callCount, 1);
    });

    test('isLoaded 加载完成后为真', () async {
      final l = DanmakuBucketLoader(
        loader: (s, e) => <DanmakuItem>[],
        bucketSize: const Duration(seconds: 60),
      );
      expect(l.isLoaded(0), isFalse);
      await l.ensureLoaded(const Duration(seconds: 30));
      expect(l.isLoaded(0), isTrue);
    });

    test('loader 抛异常 → cache 不写 → 下次还能重试', () async {
      var callCount = 0;
      final l = DanmakuBucketLoader(
        loader: (s, e) {
          callCount++;
          if (callCount == 1) throw StateError('boom');
          return [DanmakuItem(position: s, text: 'ok')];
        },
        bucketSize: const Duration(seconds: 60),
      );
      final r1 = await l.ensureLoaded(const Duration(seconds: 30));
      expect(r1, isEmpty);
      expect(l.isLoaded(0), isFalse);
      final r2 = await l.ensureLoaded(const Duration(seconds: 30));
      expect(callCount, 2);
      expect(r2, hasLength(1));
      expect(l.isLoaded(0), isTrue);
    });

    test('clear 重置全部状态', () async {
      final l = DanmakuBucketLoader(
        loader: (s, e) => <DanmakuItem>[],
        bucketSize: const Duration(seconds: 60),
      );
      await l.ensureLoaded(const Duration(seconds: 30));
      expect(l.isLoaded(0), isTrue);
      l.clear();
      expect(l.isLoaded(0), isFalse);
    });

    test('跨桶调用各自独立加载', () async {
      final calls = <(Duration, Duration)>[];
      final l = DanmakuBucketLoader(
        loader: (s, e) {
          calls.add((s, e));
          return <DanmakuItem>[];
        },
        bucketSize: const Duration(seconds: 60),
      );
      await l.ensureLoaded(const Duration(seconds: 30));
      await l.ensureLoaded(const Duration(seconds: 90));
      expect(calls, hasLength(2));
      expect(calls[1].$1, const Duration(seconds: 60));
      expect(calls[1].$2, const Duration(seconds: 120));
    });

    test('prefetchNext 加载下一桶', () async {
      final calls = <int>[];
      final l = DanmakuBucketLoader(
        loader: (s, e) {
          calls.add(s.inSeconds);
          return <DanmakuItem>[];
        },
        bucketSize: const Duration(seconds: 60),
      );
      await l.ensureLoaded(const Duration(seconds: 30));
      await l.prefetchNext(const Duration(seconds: 30));
      expect(calls, [0, 60]);
    });

    test('clear 期间飞行中的 loader 完成不污染新一代 cache', () async {
      final completer = Completer<List<DanmakuItem>>();
      final l = DanmakuBucketLoader(
        loader: (s, e) => completer.future,
        bucketSize: const Duration(seconds: 60),
      );
      // 发起加载（落到 _inFlight）
      final f = l.ensureLoaded(const Duration(seconds: 30));
      expect(l.isLoaded(0), isFalse);
      // clear → 递增 generation
      l.clear();
      // 旧 future 现在 resolve
      completer.complete([
        const DanmakuItem(position: Duration(seconds: 30), text: 'stale'),
      ]);
      await f;
      // 关键断言：旧 future 的 _loaded.add 应被门控阻止
      expect(l.isLoaded(0), isFalse,
          reason: 'clear 后飞来的 stale 响应不能让 _loaded 被错标');
    });
  });
}
