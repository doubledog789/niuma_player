import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/danmaku_models.dart';
import 'package:niuma_player/src/presentation/niuma_danmaku_controller.dart';

void main() {
  group('NiumaDanmakuController', () {
    test('默认 settings 与初始空 items', () {
      final c = NiumaDanmakuController();
      expect(c.settings, const DanmakuSettings());
      expect(c.items, isEmpty);
      c.dispose();
    });

    test('add 单条触发 notify + 维持 position 排序', () {
      final c = NiumaDanmakuController();
      var notified = 0;
      c.addListener(() => notified++);
      c.add(const DanmakuItem(position: Duration(seconds: 5), text: 'b'));
      c.add(const DanmakuItem(position: Duration(seconds: 2), text: 'a'));
      c.add(const DanmakuItem(position: Duration(seconds: 8), text: 'c'));
      expect(notified, 3);
      expect(c.items.map((e) => e.text).toList(), ['a', 'b', 'c']);
      c.dispose();
    });

    test('addAll 批量触发一次 notify', () {
      final c = NiumaDanmakuController();
      var notified = 0;
      c.addListener(() => notified++);
      c.addAll([
        const DanmakuItem(position: Duration(seconds: 5), text: 'b'),
        const DanmakuItem(position: Duration(seconds: 2), text: 'a'),
      ]);
      expect(notified, 1);
      expect(c.items.map((e) => e.text).toList(), ['a', 'b']);
      c.dispose();
    });

    test('clear 清空 items + notify', () {
      final c = NiumaDanmakuController();
      c.add(const DanmakuItem(position: Duration(seconds: 5), text: 'a'));
      var notified = 0;
      c.addListener(() => notified++);
      c.clear();
      expect(notified, 1);
      expect(c.items, isEmpty);
      c.dispose();
    });

    test('updateSettings 不同则 notify', () {
      final c = NiumaDanmakuController();
      var notified = 0;
      c.addListener(() => notified++);
      c.updateSettings(const DanmakuSettings(opacity: 0.5));
      expect(notified, 1);
      // 同值不再 notify
      c.updateSettings(const DanmakuSettings(opacity: 0.5));
      expect(notified, 1);
      c.dispose();
    });

    test('visibleAt 返回 [position-window, position] 内的 items', () {
      final c = NiumaDanmakuController();
      c.addAll([
        const DanmakuItem(position: Duration(seconds: 5), text: 'a'),
        const DanmakuItem(position: Duration(seconds: 10), text: 'b'),
        const DanmakuItem(position: Duration(seconds: 20), text: 'c'),
      ]);
      // 窗口 = [position - window, position] = [5s, 15s]
      // 5s 命中下界（含）；10s 命中；20s 超上界（排除）
      final v = c.visibleAt(const Duration(seconds: 15),
          window: const Duration(seconds: 10));
      expect(v.map((e) => e.text).toList(), ['a', 'b']);
      c.dispose();
    });

    test('visibleAt 边界 inclusive：item.position == position-window 命中', () {
      final c = NiumaDanmakuController();
      c.addAll([
        const DanmakuItem(position: Duration(seconds: 5), text: 'lower'),
        const DanmakuItem(position: Duration(seconds: 10), text: 'upper'),
      ]);
      // 窗口 = [5s, 10s]，下界与 'lower' 重合
      final v = c.visibleAt(const Duration(seconds: 10),
          window: const Duration(seconds: 5));
      expect(v.map((e) => e.text).toList(), ['lower', 'upper']);
      c.dispose();
    });

    test('visibleAt 上界 exclusive：position < item.position 不命中', () {
      final c = NiumaDanmakuController();
      c.addAll([
        const DanmakuItem(position: Duration(seconds: 5), text: 'a'),
        const DanmakuItem(position: Duration(seconds: 10), text: 'future'),
      ]);
      // currentPos=8 时，10s 还没入场，不应返回
      final v = c.visibleAt(const Duration(seconds: 8),
          window: const Duration(seconds: 5));
      expect(v.map((e) => e.text).toList(), ['a']);
      c.dispose();
    });

    test('addAll 接受 generator iterable 不丢首元素', () {
      final c = NiumaDanmakuController();
      Iterable<DanmakuItem> gen() sync* {
        yield const DanmakuItem(position: Duration(seconds: 1), text: 'first');
        yield const DanmakuItem(position: Duration(seconds: 2), text: 'second');
      }
      c.addAll(gen());
      expect(c.items.map((e) => e.text).toList(), ['first', 'second']);
      c.dispose();
    });

    test('ensureLoadedFor 转发到 BucketLoader', () async {
      final calls = <(Duration, Duration)>[];
      final c = NiumaDanmakuController(loader: (s, e) {
        calls.add((s, e));
        return [DanmakuItem(position: s, text: 'lazy')];
      });
      var notified = 0;
      c.addListener(() => notified++);
      await c.ensureLoadedFor(const Duration(seconds: 30));
      expect(calls, hasLength(1));
      expect(notified, 1); // 加载完合并 items 后 notify
      expect(c.items, hasLength(1));
      c.dispose();
    });
  });
}
