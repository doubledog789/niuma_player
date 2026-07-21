import 'package:flutter/foundation.dart';
import 'package:niuma_player/src/domain/data_source.dart';

/// 描述媒体流画质的技术性元数据，用于多码率变体比较 / 标注。
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
/// 调用方通过 [id] 标识线路；有意不重写 equality。
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

  /// 选择权重；数字越小越优先（0 为主线路，越大越靠后作 fallback）。
  final int priority;
}

/// 可携带多条可切换线路的媒体源描述符。单 URL 用
/// [NiumaMediaSource.single]，画质选择 / CDN failover 用
/// [NiumaMediaSource.lines]，首播走 [defaultLineId] 线路。
@immutable
class NiumaMediaSource {
  const NiumaMediaSource._({
    required this.lines,
    required this.defaultLineId,
    this.thumbnailVtt,
  });

  /// 用单个 [NiumaDataSource] 创建，结果只有一条 id `'default'` 的线路。
  /// [thumbnailVtt] 非 null 时立即校验（必须 http(s) 且 host 非空），
  /// 非法抛 [ArgumentError]，不延后到 fetch 时静默吞掉。
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

  /// 从显式的 [MediaLine] 列表创建。[lines] 必须非空，[defaultLineId]
  /// 必须匹配其中一条，否则抛 [ArgumentError]；[thumbnailVtt] 校验同
  /// [NiumaMediaSource.single]。
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

  /// 非 http(s) 或空 host 抛 [ArgumentError]——下游无需再校验。
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
  final List<MediaLine> lines;

  /// 默认激活线路的 [MediaLine.id]，构造时已校验存在于 [lines]。
  final String defaultLineId;

  /// 可选的 WebVTT 缩略图轨道 URL。纯数据字段——核不处理，UI 层自行
  /// fetch + 解析；thumbnail 是内容属性，所有 [lines] 共享一份。
  final String? thumbnailVtt;

  /// 返回 [defaultLineId] 对应的线路；工厂已保证存在，无需 null 检查。
  MediaLine get currentLine => lines.firstWhere((l) => l.id == defaultLineId);

  /// 返回 id 等于 [id] 的 [MediaLine]；找不到返回 `null`。
  MediaLine? lineById(String id) {
    for (final line in lines) {
      if (line.id == id) return line;
    }
    return null;
  }
}

/// 控制 source 初始化失败时是否自动尝试下一条优先级线路；
/// 希望错误直接抛到 UI 时用 [MultiSourcePolicy.manual]。
@immutable
class MultiSourcePolicy {
  const MultiSourcePolicy._({
    required this.enabled,
    required this.maxAttempts,
  });

  /// 默认策略：失败后自动尝试下一条线路，[maxAttempts] 为首次失败后
  /// 额外尝试的条数（默认 1）。
  const factory MultiSourcePolicy.autoFailover({int maxAttempts}) =
      _AutoFailover;

  /// 关闭自动 failover；init 错误直接抛到 UI。
  const factory MultiSourcePolicy.manual() = _Manual;

  /// 是否启用自动 failover。
  final bool enabled;

  /// 首次失败后额外尝试的最大线路条数；manual 时恒为 `0`。
  final int maxAttempts;
}

class _AutoFailover extends MultiSourcePolicy {
  const _AutoFailover({super.maxAttempts = 1}) : super._(enabled: true);
}

class _Manual extends MultiSourcePolicy {
  const _Manual() : super._(enabled: false, maxAttempts: 0);
}
