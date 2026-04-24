/// Source type for a [NiumaDataSource].
enum NiumaSourceType { network, asset, file }

/// Describes where a video comes from.
///
/// Mirrors the subset of [VideoPlayerController] factory constructors that
/// niuma_player supports. The underlying backend (video_player or IJK) is
/// chosen by [NiumaPlayerController].
class NiumaDataSource {
  const NiumaDataSource._({
    required this.type,
    required this.uri,
    this.headers,
  });

  /// The source type (network / asset / file).
  final NiumaSourceType type;

  /// The URI / path / asset key, depending on [type].
  final String uri;

  /// Optional HTTP headers (only meaningful for [NiumaSourceType.network]).
  final Map<String, String>? headers;

  /// Network (http/https/hls/etc.) source.
  factory NiumaDataSource.network(
    String url, {
    Map<String, String>? headers,
  }) {
    return NiumaDataSource._(
      type: NiumaSourceType.network,
      uri: url,
      headers: headers,
    );
  }

  /// Flutter asset source (packaged with the app).
  factory NiumaDataSource.asset(String assetPath) {
    return NiumaDataSource._(
      type: NiumaSourceType.asset,
      uri: assetPath,
    );
  }

  /// Local file source.
  factory NiumaDataSource.file(String filePath) {
    return NiumaDataSource._(
      type: NiumaSourceType.file,
      uri: filePath,
    );
  }

  @override
  String toString() =>
      'NiumaDataSource(type: $type, uri: $uri, headers: $headers)';
}
