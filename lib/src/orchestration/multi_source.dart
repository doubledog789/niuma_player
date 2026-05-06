import 'package:flutter/foundation.dart';
import 'package:niuma_player/src/domain/data_source.dart';

/// 描述媒体流画质的技术性元数据。
///
/// 用于在多码率播放列表中比较或标注变体。
@immutable
class MediaQuality {
  const MediaQuality({this.heightPx, this.bitrate, this.codec});

  /// 流的垂直分辨率，单位像素（例如 720、1080）。
  final int? heightPx;

  /// 流的目标码率，单位 bits-per-second（例如 1500000）。
  final int? bitrate;

  /// 编码器标识符字符串（例如 'h264'、'h265'、'av1'）。
  final String? codec;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaQuality &&
          other.heightPx == heightPx &&
          other.bitrate == bitrate &&
          other.codec == codec;

  @override
  int get hashCode => Object.hash(heightPx, bitrate, codec);
}

/// 一条可切换的播放线路——画质变体或备用 CDN 入口。
///
/// 多个 [MediaLine] 共同构成 [AutoFailoverOrchestrator] 与画质选择 UI
/// 操作的菜单。调用方通过 [id] 标识线路；该类有意不重写 equality。
@immutable
class MediaLine {
  const MediaLine({
    required this.id,
    required this.label,
    required this.source,
    this.quality,
    this.priority = 0,
  });

  /// 本线路的稳定唯一标识符（例如 'cdn-a-720'）。
  final String id;

  /// 画质选择 UI 中显示的可读标签（例如 '720P'）。
  final String label;

  /// 本线路对应的 [NiumaDataSource]。
  final NiumaDataSource source;

  /// 可选的画质元数据，描述本流的技术属性。
  final MediaQuality? quality;

  /// 选择权重；AutoFailoverOrchestrator 会优先尝试值更小的线路
  /// （priority 0 是主线路，数字越大越靠后作为 fallback）。
  final int priority;
}

/// 可携带多条可切换线路的媒体源描述符（CDN 镜像、画质变体或 failover
/// 备份）。
///
/// 简单单 URL 播放用 [NiumaMediaSource.single]；提供画质选择或 CDN
/// failover 时用 [NiumaMediaSource.lines]。首次播放使用 [defaultLineId]
/// 标识的线路。
@immutable
class NiumaMediaSource {
  const NiumaMediaSource._({
    required this.lines,
    required this.defaultLineId,
    this.thumbnailVtt,
  });

  /// 用单个 [NiumaDataSource] 创建 [NiumaMediaSource]。
  ///
  /// 结果只有一条 id 为 `'default'` 的 [MediaLine]。
  /// 在只有一个 URL 且无需画质 / CDN 切换时使用。
  ///
  /// 可选参数 [thumbnailVtt] 见 [NiumaMediaSource.thumbnailVtt]。
  /// 若非 `null`，会立即校验：必须是 http:// 或 https:// 且 host 非空。
  /// 非法 URL（asset://、file://、data:、空 host 等）抛 [ArgumentError]，
  /// 不会延后到 fetch 时静默吞掉（F5 / R2-I3）。
  factory NiumaMediaSource.single(
    NiumaDataSource source, {
    String? thumbnailVtt,
  }) {
    _validateThumbnailVtt(thumbnailVtt);
    return NiumaMediaSource._(
      lines: [
        MediaLine(id: 'default', label: 'default', source: source),
      ],
      defaultLineId: 'default',
      thumbnailVtt: thumbnailVtt,
    );
  }

  /// 从显式的 [MediaLine] 列表创建 [NiumaMediaSource]。
  ///
  /// [lines] 必须非空。[defaultLineId] 必须与 [lines] 中**恰好一条**的
  /// [MediaLine.id] 匹配，否则抛 [ArgumentError]。
  /// 用于多画质播放列表或 CDN failover 配置。
  ///
  /// 可选参数 [thumbnailVtt] 见 [NiumaMediaSource.thumbnailVtt]。
  /// 若非 `null`，会立即校验：必须是 http:// 或 https:// 且 host 非空。
  /// 非法 URL（asset://、file://、data:、空 host 等）抛 [ArgumentError]，
  /// 不会延后到 fetch 时静默吞掉（F5 / R2-I3）。
  factory NiumaMediaSource.lines({
    required List<MediaLine> lines,
    required String defaultLineId,
    String? thumbnailVtt,
  }) {
    if (lines.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'must not be empty');
    }
    if (!lines.any((l) => l.id == defaultLineId)) {
      throw ArgumentError.value(
        defaultLineId,
        'defaultLineId',
        'is not the id of any provided line',
      );
    }
    _validateThumbnailVtt(thumbnailVtt);
    return NiumaMediaSource._(
      lines: lines,
      defaultLineId: defaultLineId,
      thumbnailVtt: thumbnailVtt,
    );
  }

  /// 当 [url] 非 null 且出现以下任一情况时抛 [ArgumentError]：
  ///   - 解析出的 scheme 不是 `http://` 或 `https://`（例如
  ///     `asset://`、`file://`、`data:`）；
  ///   - 解析后 host 为空（例如 `'http:///nohost'`、纯空白字符串）。
  ///
  /// 空字符串同样会被拒绝。能通过校验的 URL 保证是语法上可用的 HTTP(S)
  /// URL——下游调用方无需再次校验，默认 fetcher 也不会拿到它本来就
  /// fetch 不了的东西。
  static void _validateThumbnailVtt(String? url) {
    if (url == null) return;
    if (url.isEmpty) {
      throw ArgumentError.value(url, 'thumbnailVtt', 'must not be empty');
    }
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } on FormatException catch (e) {
      throw ArgumentError.value(
        url,
        'thumbnailVtt',
        'not a valid URL (${e.message})',
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(
        url,
        'thumbnailVtt',
        'must use http:// or https:// scheme (got "${uri.scheme}")',
      );
    }
    if (uri.host.isEmpty) {
      throw ArgumentError.value(
        url,
        'thumbnailVtt',
        'must have a non-empty host',
      );
    }
  }

  /// 本 source 可用的有序播放线路列表。
  ///
  /// 每个元素是一条 [MediaLine]，由其 [MediaLine.id] 标识。
  /// 不要与 [NiumaMediaSource.lines] 这个工厂构造函数混淆。
  final List<MediaLine> lines;

  /// 默认激活线路对应的 [MediaLine.id]。
  ///
  /// 由构造时校验保证一定能在 [lines] 中找到对应条目。
  final String defaultLineId;

  /// 可选的 WebVTT 缩略图轨道 URL。
  ///
  /// 为 `null` 时表示不启用缩略图功能。Controller 启动后若不为 `null`，
  /// 会异步走 `SourceMiddleware` 流水线 + fetch + 解析；解析失败静默降级。
  ///
  /// 不区分清晰度——thumbnail 是内容属性，所有 [lines] 共享一份。
  final String? thumbnailVtt;

  /// 返回 [MediaLine.id] 等于 [defaultLineId] 的那条 [MediaLine]。
  ///
  /// 调用时无需做 null 检查：工厂函数保证 [defaultLineId] 一定指向某条
  /// 现存的线路。
  MediaLine get currentLine => lines.firstWhere((l) => l.id == defaultLineId);

  /// 返回 id 等于 [id] 的 [MediaLine]；找不到返回 `null`。
  MediaLine? lineById(String id) {
    for (final line in lines) {
      if (line.id == id) return line;
    }
    return null;
  }
}

/// 控制 source 初始化失败时是否自动尝试下一条优先级线路。
///
/// 由 [AutoFailoverOrchestrator]（M7 中的独立 helper）用于在 init 失败
/// 后按优先级顺序推进 [MediaLine]。M7 中 controller 自身**不**消费本
/// policy——接线推迟到后续 milestone。
///
/// 当希望错误直接抛到 UI、不做任何自动重试时使用
/// [MultiSourcePolicy.manual]。
@immutable
class MultiSourcePolicy {
  const MultiSourcePolicy._({
    required this.enabled,
    required this.maxAttempts,
  });

  /// 默认策略：失败后自动尝试下一条线路。
  ///
  /// [maxAttempts] 表示在首次失败之后额外尝试的线路条数（默认 `1`，
  /// 即在放弃前再尝试一条）。
  const factory MultiSourcePolicy.autoFailover({int maxAttempts}) =
      _AutoFailover;

  /// 关闭自动 failover；init 错误直接抛到 UI。
  const factory MultiSourcePolicy.manual() = _Manual;

  /// 是否启用自动 failover。
  ///
  /// [MultiSourcePolicy.autoFailover] 时为 `true`，
  /// [MultiSourcePolicy.manual] 时为 `false`。
  final bool enabled;

  /// 首次失败后额外尝试的最大线路条数。
  ///
  /// 仅在 [enabled] 为 `true` 时有意义；对
  /// [MultiSourcePolicy.manual] 永远为 `0`。
  final int maxAttempts;
}

class _AutoFailover extends MultiSourcePolicy {
  const _AutoFailover({super.maxAttempts = 1})
      : super._(enabled: true);
}

class _Manual extends MultiSourcePolicy {
  const _Manual() : super._(enabled: false, maxAttempts: 0);
}
