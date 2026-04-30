import 'dart:collection';

import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:flutter/widgets.dart' show ImageProvider, NetworkImage;

/// 按 sprite URL 去重的 [ImageProvider] 缓存，支持 LRU 上限。
///
/// 同一 `NiumaPlayerController` 生命周期内复用；dispose 时清空 controller-local
/// 引用并 evict 全局 [PaintingBinding.imageCache] 中已解码的位图。
class ThumbnailCache {
  /// 创建一个 thumbnail 缓存。
  ///
  /// [maxEntries] 默认 32，覆盖长视频典型的 sprite 数（4 小时视频，每张 sprite
  /// ~120 帧，总共约 24 张 sprite，留 8 张 headroom 应对 line / quality 切换
  /// 时短暂的双套缓存。
  ///
  /// 调大估算：
  /// - 总 sprite 数 ≈ ⌈视频时长(s) / cue 时长(s) / 每 sprite 帧数⌉
  /// - 例：6 小时视频 + 5s/cue + 100 frames/sprite ≈ 43 张 → 设 maxEntries=64
  /// - 调大不会增加内存几何，只是延长 LRU 链——实际驻留内存仍由
  ///   [PaintingBinding.imageCache] 的 maxBytes (默认 100MB) 兜底。
  ThumbnailCache({this.maxEntries = 32});

  /// 单个 source 同时缓存的最大 sprite 数。短视频通常 1 张就够，
  /// 长视频按 100 张缩略图 / sprite 估，[maxEntries]=32 能覆盖约 3200 帧。
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
      // 淘汰最旧的，并把它从全局 imageCache 中 evict —— 否则解码后的位图
      // 可能继续占住 RAM 直到下次 GC。
      final oldestKey = _entries.keys.first;
      final oldestProvider = _entries.remove(oldestKey);
      if (oldestProvider != null) {
        _evictFromGlobalImageCache(oldestProvider);
      }
    }
    return provider;
  }

  /// 是否已经缓存过 [url]。
  bool contains(String url) => _entries.containsKey(url);

  /// 清空所有缓存条目，并 evict 全局 [PaintingBinding.imageCache] 中
  /// 对应的解码位图。否则即使 controller 已 dispose，sprite 像素仍可能
  /// 占住 imageCache 直到 GC（I1/I8）。
  void clear() {
    for (final provider in _entries.values) {
      _evictFromGlobalImageCache(provider);
    }
    _entries.clear();
  }

  static void _evictFromGlobalImageCache(ImageProvider provider) {
    // PaintingBinding 在纯 Dart 环境（无 Flutter binding）下可能是 null。
    // 测试代码会触发 binding 初始化；生产环境一定有 binding。这里防御一下。
    final binding = PaintingBinding.instance;
    binding.imageCache.evict(provider);
  }
}
