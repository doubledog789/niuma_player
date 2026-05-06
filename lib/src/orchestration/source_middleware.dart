import 'package:niuma_player/src/domain/data_source.dart';

/// 在 [NiumaDataSource] 进入播放后端之前对其进行变换。
///
/// 在每次涉及网络的操作上都会执行——`initialize`、`switchLine`、重试——
/// 让每次尝试都能拿到新的 headers 或重新签名后的 URL。
abstract class SourceMiddleware {
  const SourceMiddleware();

  /// 对 [input] 进行变换并返回（可能被修改后的）数据源。
  Future<NiumaDataSource> apply(NiumaDataSource input);
}

/// 把一组固定 HTTP headers 合并到每个网络 [NiumaDataSource] 上。
///
/// 用来注入鉴权 token、Referer 等所有网络请求都必须携带的静态
/// 请求头。
class HeaderInjectionMiddleware extends SourceMiddleware {
  /// 创建一个把 [headers] 合并到网络 source 的 middleware。
  const HeaderInjectionMiddleware(this.headers);

  /// 要合并到数据源原有 headers 中的 headers。
  final Map<String, String> headers;

  /// 非网络 source 原样返回；否则返回一个新的网络 source，其
  /// headers 为原 headers 与 [headers] 合并的结果。
  @override
  Future<NiumaDataSource> apply(NiumaDataSource input) async {
    if (input.type != NiumaSourceType.network) return input;
    return NiumaDataSource.network(
      input.uri,
      headers: {...?input.headers, ...headers},
    );
  }
}

/// 用调用方提供的签名函数把每个网络 [NiumaDataSource] 的 URL 替换成
/// 新签好名的 URL。
///
/// 每次 [apply] 调用都会用原始 URL 触发 signer，并用结果构建一个新的
/// 网络 source，原 headers 原样保留。非网络 source 直接返回，不调
/// signer。
class SignedUrlMiddleware extends SourceMiddleware {
  /// 创建一个 middleware，它调用 [_signer] 把每个原始 URL 映射成签名后
  /// 的 URL。[_signer] 接收原始 URL，必须返回签名后的 URL。
  SignedUrlMiddleware(this._signer);

  final Future<String> Function(String rawUrl) _signer;

  /// 非网络 source 原样返回；否则返回一个新的网络 source，URI 为签名
  /// 后的 URL，原 headers 透传。
  @override
  Future<NiumaDataSource> apply(NiumaDataSource input) async {
    if (input.type != NiumaSourceType.network) return input;
    final signedUrl = await _signer(input.uri);
    return NiumaDataSource.network(signedUrl, headers: input.headers);
  }
}

/// 把 [input] 依次经过 [middlewares] 中每个 middleware（从左到右），返回
/// 最终变换后的 [NiumaDataSource]。
///
/// - middleware 按顺序应用：每个的输出作为下一个的输入。
/// - [middlewares] 为空时立即短路，原样返回 [input]（同一对象，不是副本）。
/// - 每个 middleware 只看到上一个的输出，因此无论 middleware 类型如何，
///   组合都能干净进行。
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
