import '../domain/data_source.dart';

/// Transforms a [NiumaDataSource] before it reaches the playback backend.
///
/// Applied on every operation that touches the network — `initialize`,
/// `switchLine`, and retry — so each attempt gets fresh headers or a
/// freshly signed URL.
abstract class SourceMiddleware {
  const SourceMiddleware();

  /// Transforms [input] and returns the (possibly modified) data source.
  Future<NiumaDataSource> apply(NiumaDataSource input);
}

/// Merges a fixed set of HTTP headers into every network [NiumaDataSource].
///
/// Use this to inject authentication tokens, Referer headers, or any other
/// static request headers that every network request must carry.
class HeaderInjectionMiddleware extends SourceMiddleware {
  /// Creates a middleware that merges [headers] into network sources.
  const HeaderInjectionMiddleware(this.headers);

  /// The headers to merge into the data source's existing headers map.
  final Map<String, String> headers;

  /// Returns [input] unchanged for non-network sources; otherwise returns a
  /// new network source with [headers] merged on top of any existing headers.
  @override
  Future<NiumaDataSource> apply(NiumaDataSource input) async {
    if (input.type != NiumaSourceType.network) return input;
    return NiumaDataSource.network(
      input.uri,
      headers: {...?input.headers, ...headers},
    );
  }
}
