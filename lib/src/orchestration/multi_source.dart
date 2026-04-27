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

/// A media source descriptor that may carry multiple switchable lines
/// (CDN mirrors, quality variants, or failover backups).
///
/// Use [NiumaMediaSource.single] for simple single-URL playback, or
/// [NiumaMediaSource.lines] when offering quality selection or CDN failover.
/// The line identified by [defaultLineId] is used on first playback.
@immutable
class NiumaMediaSource {
  const NiumaMediaSource._({
    required this.lines,
    required this.defaultLineId,
  });

  /// Creates a [NiumaMediaSource] backed by a single [NiumaDataSource].
  ///
  /// The resulting source has one [MediaLine] with id `'default'`.
  /// Use this when there is only one URL and no quality/CDN switching needed.
  factory NiumaMediaSource.single(NiumaDataSource source) {
    return NiumaMediaSource._(
      lines: [
        MediaLine(id: 'default', label: 'default', source: source),
      ],
      defaultLineId: 'default',
    );
  }

  /// Creates a [NiumaMediaSource] from an explicit list of [MediaLine]s.
  ///
  /// [lines] must be non-empty. [defaultLineId] must match the [MediaLine.id]
  /// of exactly one entry in [lines]; an [ArgumentError] is thrown otherwise.
  /// Use this for multi-quality playlists or CDN failover configurations.
  factory NiumaMediaSource.lines({
    required List<MediaLine> lines,
    required String defaultLineId,
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
    return NiumaMediaSource._(lines: lines, defaultLineId: defaultLineId);
  }

  /// The ordered list of playback lines available for this source.
  ///
  /// Each entry is a [MediaLine] identified by its [MediaLine.id].
  /// Do not confuse with the [NiumaMediaSource.lines] factory constructor.
  final List<MediaLine> lines;

  /// The [MediaLine.id] of the line that is active by default.
  ///
  /// Guaranteed to match one entry in [lines] by construction.
  final String defaultLineId;

  /// Returns the [MediaLine] whose [MediaLine.id] equals [defaultLineId].
  ///
  /// Safe to call without null-check: the factories enforce that
  /// [defaultLineId] always refers to an existing line.
  MediaLine get currentLine => lines.firstWhere((l) => l.id == defaultLineId);

  /// Returns the [MediaLine] with the given [id], or `null` if not found.
  MediaLine? lineById(String id) {
    for (final line in lines) {
      if (line.id == id) return line;
    }
    return null;
  }
}

/// Controls whether the controller automatically tries the next priority line
/// when a source fails to initialise.
///
/// Use [MultiSourcePolicy.autoFailover] (the default) to have the controller
/// silently advance through available [MediaLine]s on init failure.
/// Use [MultiSourcePolicy.manual] when you want errors to propagate directly
/// to the UI without any automatic retry.
@immutable
class MultiSourcePolicy {
  const MultiSourcePolicy._({
    required this.enabled,
    required this.maxAttempts,
  });

  /// The default policy: automatically try the next line on failure.
  ///
  /// [maxAttempts] is the number of additional lines to attempt after the
  /// first failure (defaults to `1`, meaning one extra line is tried before
  /// giving up).
  const factory MultiSourcePolicy.autoFailover({int maxAttempts}) =
      _AutoFailover;

  /// Disables automatic failover; init errors propagate directly to the UI.
  const factory MultiSourcePolicy.manual() = _Manual;

  /// Whether automatic failover is active.
  ///
  /// `true` for [MultiSourcePolicy.autoFailover], `false` for
  /// [MultiSourcePolicy.manual].
  final bool enabled;

  /// Maximum number of additional lines to attempt after the first failure.
  ///
  /// Only meaningful when [enabled] is `true`; always `0` for
  /// [MultiSourcePolicy.manual].
  final int maxAttempts;
}

class _AutoFailover extends MultiSourcePolicy {
  const _AutoFailover({int maxAttempts = 1})
      : super._(enabled: true, maxAttempts: maxAttempts);
}

class _Manual extends MultiSourcePolicy {
  const _Manual() : super._(enabled: false, maxAttempts: 0);
}
