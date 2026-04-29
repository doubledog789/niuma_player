import 'thumbnail_cache.dart';
import 'thumbnail_track.dart';

/// 把 [Duration] 映射成 [ThumbnailFrame]：在 cues 里找包含 position 的那条，
/// 用 baseUrl 解析相对 sprite URL，从 cache 拿对应 ImageProvider。
abstract class ThumbnailResolver {
  ThumbnailResolver._();

  /// 找到包含 [position] 的 cue 并返回 frame；如果没有 cue 命中返回 null。
  ///
  /// - [cues]：已解析的 thumbnail cue 列表（按 start 升序）。
  /// - [baseUrl]：VTT 文件的 URL，用于解析相对 sprite 引用。
  /// - [cache]：sprite URL → [ThumbnailFrame.image] 缓存。
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
    return ThumbnailFrame(
      image: cache.getOrCreate(absoluteUrl),
      region: cue.region,
    );
  }

  static WebVttCue? _findCue(List<WebVttCue> cues, Duration position) {
    // cues 按 start 升序。线性扫描足够（cue 数量 typical 几十~几百）。
    // 后续若需优化可改成二分。
    for (final cue in cues) {
      if (cue.contains(position)) return cue;
    }
    return null;
  }

  static String _resolveSpriteUrl(String spriteUrl, String baseUrl) {
    if (spriteUrl.startsWith('http://') || spriteUrl.startsWith('https://')) {
      return spriteUrl;
    }
    final base = Uri.parse(baseUrl);
    return base.resolve(spriteUrl).toString();
  }
}
