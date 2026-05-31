import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ImageProvider;

/// `controller.thumbnailFor(...)` 的返回值：图片提供者 + 在原图里的裁剪矩形。
///
/// 两个 frame 相等当且仅当 `image` 是同一个 [ImageProvider] 实例（用 identity
/// 比较）且 `region` 相等。用 identity 比较 image 而不是 ==，是因为
/// [ImageProvider] 子类（如 NetworkImage）的 == 走 url，我们的 cache 已经按
/// URL 去重，identity 等价于 URL 等价但更便宜。
///
/// **稳定性边界（R2-S1）**：[ThumbnailCache] 在 LRU 容量内保证同 URL 返回
/// identical 实例；一旦该 sprite 被 evict（视频很长 / 切线路 / sprite 数
/// 超过 cache `maxEntries`），下一次再查会拿到不同的 [ImageProvider] 实例，
/// `==` 会失败——即使内容相同。这是预期行为：
///
///   - **安全用法**：在 cache hit 期间用 `==` 短路 setState
///     （e.g. `if (next == _shown) return;`）。Cache miss 后 `==` 返回
///     false，仅意味着会多触发一次 setState，不会出错。
///   - **不安全用法**：把 frame 当跨长时间 / 大量线路切换的稳定 dedup key。
///     需要"内容相等"语义时，比较 [region] + 上层记下来的 sprite URL。
@immutable
class ThumbnailFrame {
  /// 创建一个 thumbnail frame。
  const ThumbnailFrame({required this.image, required this.region});

  /// sprite 图的 [ImageProvider]（通常是 NetworkImage）。
  final ImageProvider image;

  /// 在 sprite 图内的裁剪矩形（像素坐标）。
  final Rect region;

  @override
  bool operator ==(Object other) =>
      other is ThumbnailFrame &&
      identical(image, other.image) &&
      region == other.region;

  @override
  int get hashCode => Object.hash(identityHashCode(image), region);
}
