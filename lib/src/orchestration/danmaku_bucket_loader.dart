import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:niuma_player/src/orchestration/danmaku_models.dart';

/// 60s 桶 lazy loader：dedup 并发请求，缓存已加载桶，错误不污染 cache。
class DanmakuBucketLoader {
  /// 构造一个 loader。loader 为 null 时所有 ensureLoaded 立即返回空。
  DanmakuBucketLoader({
    required this.loader,
    required this.bucketSize,
  });

  /// 业务侧 lazy load 回调。
  final DanmakuLoader? loader;

  /// 桶大小（默认 60s 与后端一致）。
  final Duration bucketSize;

  // 已加载完成的桶 index → 永久 true。
  final Set<int> _loaded = <int>{};
  // 进行中的 future（dedup 用）。完成后从 map 移除；成功的同时写入 _loaded。
  final Map<int, Future<List<DanmakuItem>>> _inFlight =
      <int, Future<List<DanmakuItem>>>{};
  // 代际计数器：clear() 时递增，让飞行中的 future 知道自己已被作废。
  int _generation = 0;

  /// 桶 index 计算。
  int _indexOf(Duration position) =>
      position.inMilliseconds ~/ bucketSize.inMilliseconds;

  /// 检查指定桶 index 是否已加载完成。
  bool isLoaded(int bucketIndex) => _loaded.contains(bucketIndex);

  /// 确保 [position] 所在桶已加载。已加载或加载中则返回缓存 future / 空。
  Future<List<DanmakuItem>> ensureLoaded(Duration position) {
    final loader = this.loader;
    if (loader == null) return Future.value(const <DanmakuItem>[]);

    final idx = _indexOf(position);
    if (_loaded.contains(idx)) return Future.value(const <DanmakuItem>[]);

    final inFlight = _inFlight[idx];
    if (inFlight != null) return inFlight;

    final start = Duration(milliseconds: idx * bucketSize.inMilliseconds);
    final end = Duration(milliseconds: (idx + 1) * bucketSize.inMilliseconds);

    final gen = _generation;
    final future = Future<List<DanmakuItem>>(() async {
      try {
        final result = await loader(start, end);
        if (_generation == gen) _loaded.add(idx);
        return result;
      } catch (e, st) {
        debugPrint('[DanmakuBucketLoader] bucket $idx 加载失败：$e\n$st');
        return const <DanmakuItem>[];
      } finally {
        if (_generation == gen) _inFlight.remove(idx);
      }
    });
    _inFlight[idx] = future;
    return future;
  }

  /// 预取下一桶（建议 position 进入当前桶 80% 时调用）。
  Future<List<DanmakuItem>> prefetchNext(Duration position) {
    final next = Duration(
        milliseconds: (_indexOf(position) + 1) * bucketSize.inMilliseconds);
    return ensureLoaded(next);
  }

  /// 切换视频源时清空。
  ///
  /// 内部用 generation counter 让飞行中的 loader 在 resolve 时自动作废
  /// 写入，避免旧 source 的迟到响应污染新 source 的 cache。
  void clear() {
    _generation++;
    _loaded.clear();
    _inFlight.clear();
  }
}
