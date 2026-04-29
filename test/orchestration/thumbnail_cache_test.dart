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
