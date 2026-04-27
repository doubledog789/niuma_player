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

/// Replaces the URL of every network [NiumaDataSource] with a freshly signed
/// URL produced by the caller-supplied signer function.
///
/// On each [apply] call the signer is invoked with the raw URL and the result
/// is used to build a new network source that carries the original headers
/// unchanged. Non-network sources are returned as-is without calling the
/// signer.
class SignedUrlMiddleware extends SourceMiddleware {
  /// Creates a middleware that calls [_signer] to map each raw URL to a
  /// signed URL. [_signer] receives the raw URL and must return the signed URL.
  SignedUrlMiddleware(this._signer);

  final Future<String> Function(String rawUrl) _signer;

  /// Returns [input] unchanged for non-network sources; otherwise returns a
  /// new network source whose URI is the signed URL with the original headers
  /// passed through.
  @override
  Future<NiumaDataSource> apply(NiumaDataSource input) async {
    if (input.type != NiumaSourceType.network) return input;
    final signedUrl = await _signer(input.uri);
    return NiumaDataSource.network(signedUrl, headers: input.headers);
  }
}

/// Runs [input] through each middleware in [middlewares] left-to-right,
/// returning the final transformed [NiumaDataSource].
///
/// - Middlewares are applied in order: the output of each middleware becomes
///   the input to the next one.
/// - An empty [middlewares] list short-circuits immediately, returning [input]
///   unchanged (the identical object, not a copy).
/// - Each middleware sees only the output of the previous one, so transformations
///   compose cleanly regardless of middleware type.
Future<NiumaDataSource> runSourceMiddlewares(
  NiumaDataSource input,
  List<SourceMiddleware> middlewares,
) async {
  if (middlewares.isEmpty) return input;
  var current = input;
  for (final m in middlewares) {
    current = await m.apply(current);
  }
  return current;
}
