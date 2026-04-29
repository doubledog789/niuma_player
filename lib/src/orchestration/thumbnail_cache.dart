import 'dart:collection';

import 'package:flutter/widgets.dart' show ImageProvider, NetworkImage;

/// 按 sprite URL 去重的 [ImageProvider] 缓存，支持 LRU 上限。
///
/// 同一 `NiumaPlayerController` 生命周期内复用；dispose 时清空。
class ThumbnailCache {
  /// 创建一个 thumbnail 缓存。
  ///
  /// [maxEntries] 默认 8，能覆盖长视频常见的多张 sprite。
  ThumbnailCache({this.maxEntries = 8});

  /// 单个 source 同时缓存的最大 sprite 数。短视频通常 1 张就够，
  /// 长视频按 100 张缩略图 / sprite 估，[maxEntries]=8 能覆盖 800 帧。
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

  /// 是否已经缓存过 [url]。
  bool contains(String url) => _entries.containsKey(url);

  /// 清空所有缓存条目。
  void clear() => _entries.clear();
}
