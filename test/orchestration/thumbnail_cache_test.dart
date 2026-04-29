import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/thumbnail_cache.dart';

void main() {
  // ThumbnailCache.clear() now reaches into PaintingBinding.imageCache, so
  // the test binding must be initialised before any cache test runs.
  TestWidgetsFlutterBinding.ensureInitialized();

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

    // I1/I8: clear() 必须 evict 全局 PaintingBinding.instance.imageCache 中
    // 已解码的位图，否则 sprite 像素一直占住 RAM 直到 GC 偶然回收。
    test('clear() 同时 evict PaintingBinding.imageCache 中的解码位图（I1/I8）',
        () {
      final cache = ThumbnailCache();
      final providerA = cache.getOrCreate('https://x/a.jpg');
      final providerB = cache.getOrCreate('https://x/b.jpg');

      // 模拟"图已经走过 ImageStream → 解码 → 进 imageCache" 的状态：
      // 直接往全局 imageCache putIfAbsent 一条假记录。
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.clear();
      imageCache.evict(providerA);
      imageCache.evict(providerB);

      // 让两个 provider 进 imageCache 的活跃集合（用 putIfAbsent 占位，
      // 不真的解码——测试目的只是验证 evict 被调）。
      final keyA = providerA;
      final keyB = providerB;
      // ignore: invalid_use_of_protected_member
      imageCache.putIfAbsent(keyA, () => _NoOpImageStreamCompleter());
      // ignore: invalid_use_of_protected_member
      imageCache.putIfAbsent(keyB, () => _NoOpImageStreamCompleter());

      expect(imageCache.containsKey(providerA), isTrue);
      expect(imageCache.containsKey(providerB), isTrue);

      cache.clear();

      expect(imageCache.containsKey(providerA), isFalse,
          reason: 'clear() must evict from PaintingBinding.imageCache');
      expect(imageCache.containsKey(providerB), isFalse);
      expect(cache.contains('https://x/a.jpg'), isFalse);
    });

    // TG6 (commit 4 锁定 default)；提前补在 commit 2 也方便后续 commit。
    // 不破坏既有 API；现在还是 8，commit 3 再调 32。这里先放占位。
  });
}

/// A no-op [ImageStreamCompleter] used only to occupy a slot in the global
/// [PaintingBinding.imageCache] for tests. It never resolves and never errors.
class _NoOpImageStreamCompleter extends ImageStreamCompleter {}

