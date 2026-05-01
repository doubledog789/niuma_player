import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/danmaku_track_allocator.dart';

void main() {
  late DanmakuTrackAllocator a;

  setUp(() {
    a = DanmakuTrackAllocator();
    // 屏幕 360x200，rowHeight 30，displayArea 100% → scroll 6 行 / top 3 / bottom 3
    a.resize(width: 360, height: 200, rowHeight: 30, areaPercent: 1.0);
  });

  group('scroll 模式', () {
    test('first-fit 从 row 0 开始', () {
      final r = a.allocateScrollTrack(
          textWidth: 100,
          scrollDuration: const Duration(seconds: 10),
          screenWidth: 360,
          nowMs: 0);
      expect(r, 0);
    });

    test('占用未让出时第二条进 row 1', () {
      a.allocateScrollTrack(
          textWidth: 200,
          scrollDuration: const Duration(seconds: 10),
          screenWidth: 360,
          nowMs: 0);
      // 100ms 后再来一条：第一条 progress=0.01，右边沿 = 360 - 560*0.01 + 200 = 554.4 > 352 → row 0 仍占用
      final r = a.allocateScrollTrack(
          textWidth: 100,
          scrollDuration: const Duration(seconds: 10),
          screenWidth: 360,
          nowMs: 100);
      expect(r, 1);
    });

    test('满轨返回 -1', () {
      for (var i = 0; i < 6; i++) {
        a.allocateScrollTrack(
            textWidth: 200,
            scrollDuration: const Duration(seconds: 10),
            screenWidth: 360,
            nowMs: 0);
      }
      final r = a.allocateScrollTrack(
          textWidth: 100,
          scrollDuration: const Duration(seconds: 10),
          screenWidth: 360,
          nowMs: 0);
      expect(r, -1);
    });

    test('上一条让出后该 row 复用', () {
      a.allocateScrollTrack(
          textWidth: 100,
          scrollDuration: const Duration(seconds: 10),
          screenWidth: 360,
          nowMs: 0);
      // 10s 后第一条已离开屏幕（progress=1.0）
      final r = a.allocateScrollTrack(
          textWidth: 100,
          scrollDuration: const Duration(seconds: 10),
          screenWidth: 360,
          nowMs: 10000);
      expect(r, 0);
    });
  });

  group('topFixed 模式', () {
    test('first-fit 从 row 0', () {
      final r = a.allocateTopFixedTrack(
          fixedDuration: const Duration(seconds: 5), nowMs: 0);
      expect(r, 0);
    });

    test('窗口内同 row 不可重入', () {
      a.allocateTopFixedTrack(
          fixedDuration: const Duration(seconds: 5), nowMs: 0);
      final r = a.allocateTopFixedTrack(
          fixedDuration: const Duration(seconds: 5), nowMs: 100);
      expect(r, 1);
    });

    test('窗口外可复用', () {
      a.allocateTopFixedTrack(
          fixedDuration: const Duration(seconds: 5), nowMs: 0);
      final r = a.allocateTopFixedTrack(
          fixedDuration: const Duration(seconds: 5), nowMs: 6000);
      expect(r, 0);
    });

    test('top 满轨返回 -1', () {
      for (var i = 0; i < 3; i++) {
        a.allocateTopFixedTrack(
            fixedDuration: const Duration(seconds: 5), nowMs: 0);
      }
      final r = a.allocateTopFixedTrack(
          fixedDuration: const Duration(seconds: 5), nowMs: 100);
      expect(r, -1);
    });
  });

  group('bottomFixed 模式', () {
    test('独立于 top 模式', () {
      for (var i = 0; i < 3; i++) {
        a.allocateTopFixedTrack(
            fixedDuration: const Duration(seconds: 5), nowMs: 0);
      }
      final r = a.allocateBottomFixedTrack(
          fixedDuration: const Duration(seconds: 5), nowMs: 0);
      expect(r, 0);
    });
  });

  group('clear / resize', () {
    test('clear 清空全部占用', () {
      a.allocateScrollTrack(
          textWidth: 200,
          scrollDuration: const Duration(seconds: 10),
          screenWidth: 360,
          nowMs: 0);
      a.clear();
      final r = a.allocateScrollTrack(
          textWidth: 100,
          scrollDuration: const Duration(seconds: 10),
          screenWidth: 360,
          nowMs: 0);
      expect(r, 0);
    });

    test('resize 后 row count 更新', () {
      a.resize(width: 360, height: 100, rowHeight: 30, areaPercent: 1.0);
      // 100/30 = 3 行 scroll
      expect(a.scrollRowCount, 3);
    });

    test('areaPercent 缩减显示区', () {
      a.resize(width: 360, height: 200, rowHeight: 30, areaPercent: 0.5);
      // 200*0.5/30 = 3 行
      expect(a.scrollRowCount, 3);
    });
  });
}
