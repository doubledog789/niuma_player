import 'package:flutter/foundation.dart';
import '../domain/data_source.dart';

/// Technical metadata describing the quality of a media stream.
///
/// Used to compare or label variants in a multi-quality playlist.
@immutable
class MediaQuality {
  const MediaQuality({this.heightPx, this.bitrate, this.codec});

  /// Vertical resolution of the stream, in pixels (e.g. 720, 1080).
  final int? heightPx;

  /// Target bitrate of the stream, in bits-per-second (e.g. 1500000).
  final int? bitrate;

  /// Codec identifier string (e.g. 'h264', 'h265', 'av1').
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

/// One switchable playback line — a quality variant or a backup CDN entry.
///
/// A collection of [MediaLine]s makes up the menu that
/// [AutoFailoverOrchestrator] and quality-selector UI operate on.
/// Callers identify lines by [id]; equality is intentionally not overridden.
@immutable
class MediaLine {
  const MediaLine({
    required this.id,
    required this.label,
    required this.source,
    this.quality,
    this.priority = 0,
  });

  /// Stable unique identifier for this line (e.g. 'cdn-a-720').
  final String id;

  /// Human-readable label shown in quality-picker UI (e.g. '720P').
  final String label;

  /// The [NiumaDataSource] that backs this line.
  final NiumaDataSource source;

  /// Optional quality metadata describing this stream's technical properties.
  final MediaQuality? quality;

  /// Selection weight; higher priority tried first by AutoFailoverOrchestrator.
  final int priority;
}
