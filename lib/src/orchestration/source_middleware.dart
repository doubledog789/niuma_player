import 'package:niuma_player/src/domain/data_source.dart';

/// 在 [NiumaDataSource] 进入播放后端之前对其进行变换。
/// 每次涉网操作（initialize / switchLine / 重试）都会执行，
/// 让每次尝试拿到新 headers 或重签名 URL。
abstract class SourceMiddleware {
  const SourceMiddleware();

  /// 对 [input] 进行变换并返回（可能被修改后的）数据源。
  Future<NiumaDataSource> apply(NiumaDataSource input);
}

/// 把一组固定 HTTP headers 合并到每个网络 [NiumaDataSource] 上，
/// 用于注入鉴权 token、Referer 等静态请求头。
class HeaderInjectionMiddleware extends SourceMiddleware {
  /// 创建一个把 [headers] 合并到网络 source 的 middleware。
  const HeaderInjectionMiddleware(this.headers);

  /// 要合并到数据源原有 headers 中的 headers。
  final Map<String, String> headers;

  /// 非网络 source 原样返回；否则合并 [headers] 返回新的网络 source。
  @override
  Future<NiumaDataSource> apply(NiumaDataSource input) async {
    if (input.type != NiumaSourceType.network) return input;
    return NiumaDataSource.network(
      input.uri,
      headers: {...?input.headers, ...headers},
    );
  }
}

/// 用调用方提供的签名函数把每个网络 [NiumaDataSource] 的 URL 换成
/// 签名后的 URL，原 headers 保留；非网络 source 不调 signer。
class SignedUrlMiddleware extends SourceMiddleware {
  /// 创建 middleware；[_signer] 接收原始 URL，返回签名后的 URL。
  SignedUrlMiddleware(this._signer);

  final Future<String> Function(String rawUrl) _signer;

  /// 非网络 source 原样返回；否则 URI 换签名 URL，headers 透传。
  @override
  Future<NiumaDataSource> apply(NiumaDataSource input) async {
    if (input.type != NiumaSourceType.network) return input;
    final signedUrl = await _signer(input.uri);
    return NiumaDataSource.network(signedUrl, headers: input.headers);
  }
}

/// 把 [input] 从左到右依次经过 [middlewares]（前者输出为后者输入），
/// 返回最终变换结果；空列表短路原样返回。
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
