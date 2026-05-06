import '../orchestration/thumbnail_track.dart';
import 'thumbnail_cache.dart';
import 'thumbnail_frame.dart';

/// 把 [Duration] 映射成 [ThumbnailFrame]：在 cues 里找包含 position 的那条，
/// 用 baseUrl 解析相对 sprite URL，从 cache 拿对应 ImageProvider。
abstract class ThumbnailResolver {
  ThumbnailResolver._();

  /// 找到包含 [position] 的 cue 并返回 frame；如果没有 cue 命中返回 null。
  ///
  /// - [cues]：已解析的 thumbnail cue 列表（按 start 升序）。复杂度 O(log n)
  ///   —— 内部用二分查找，对长视频 thousands-of-cue 场景每次查询不会成为瓶颈。
  /// - [baseUrl]：VTT 文件的 URL，用于解析相对 sprite 引用。
  /// - [cache]：sprite URL → [ThumbnailFrame.image] 缓存。
  ///
  /// **永不抛**：任何异常（cue 列表不合法、baseUrl 无法解析、相对解析失败）
  /// 一律 swallow 后返回 `null`。这是 [NiumaPlayerController.thumbnailFor] 的
  /// 公开契约，调用方依赖它来保证 UI 层的安全性。
  static ThumbnailFrame? resolve({
    required Duration position,
    required List<WebVttCue> cues,
    required String baseUrl,
    required ThumbnailCache cache,
  }) {
    if (cues.isEmpty) return null;
    final cue = _findCue(cues, position);
    if (cue == null) return null;
    final absoluteUrl = _resolveSpriteUrl(cue.spriteUrl, baseUrl);
    if (absoluteUrl == null) return null;
    return ThumbnailFrame(
      image: cache.getOrCreate(absoluteUrl),
      region: cue.region,
    );
  }

  /// 二分查找包含 [position] 的 cue。前提：[cues] 按 [WebVttCue.start] 升序，
  /// cue 之间不重叠（典型 VTT thumbnail track 满足，[WebVttParser.parseThumbnails]
  /// 也保留了 VTT 文件里的顺序）。复杂度 O(log n)。
  ///
  /// **传入无序 / 重叠 cues 的行为是未定义的**：可能命中错误的 cue，也可能漏掉
  /// 应当命中的 cue。出于性能考虑这里**不做** runtime assert——thousands-of-cue
  /// 场景下每次 resolve 都跑 O(n) 校验等于把二分查找的收益吞掉。调用方手工
  /// 构造 cue 时需要自行保证有序（TG3）。
  ///
  /// 半开区间语义 `[start, end)`：`position == cue.start` 命中，
  /// `position == cue.end` 不命中（落入下一 cue 或返回 null）。
  static WebVttCue? _findCue(List<WebVttCue> cues, Duration position) {
    var lo = 0;
    var hi = cues.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final cue = cues[mid];
      if (position < cue.start) {
        hi = mid - 1;
      } else if (position >= cue.end) {
        lo = mid + 1;
      } else {
        // start <= position < end —— 命中。
        return cue;
      }
    }
    return null;
  }

  /// 解析 [spriteUrl]（可能是相对路径）为绝对 URL。失败返回 `null`。
  ///
  /// 包了一层 try/catch：恶意 / 错误格式的 baseUrl 会让 [Uri.parse] 抛
  /// `FormatException`——为遵守 [resolve] 的"永不抛"契约必须 swallow（C5）。
  static String? _resolveSpriteUrl(String spriteUrl, String baseUrl) {
    if (spriteUrl.startsWith('http://') || spriteUrl.startsWith('https://')) {
      return spriteUrl;
    }
    try {
      final base = Uri.parse(baseUrl);
      return base.resolve(spriteUrl).toString();
    } catch (_) {
      return null;
    }
  }
}
