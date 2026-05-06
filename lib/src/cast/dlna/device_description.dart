import 'dart:io';

/// 解析设备 description XML 拿 AVTransport 服务的 controlURL（绝对 URL）。
/// XML 格式（UPnP 1.0 spec）：
///
/// ```xml
/// <root>
///   <device>
///     <serviceList>
///       <service>
///         <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
///         <controlURL>/AVTransport/Control</controlURL>
///       </service>
///       ...
///     </serviceList>
///   </device>
/// </root>
/// ```
///
/// `controlURL` 可能是相对路径（如 `/AVTransport/Control`）或绝对
/// （如 `http://1.2.3.4:8080/AVTransport/Control`）——本函数返**绝对 URL**。
String? parseAVTransportControlUrl({
  required String descriptionXml,
  required String descriptionUrl,
}) {
  // 简化解析：找包含 AVTransport 的 service 块，提取里面的 controlURL。
  // 不引第三方 XML lib——SDK 不带 xml 依赖以保体积。
  final services = RegExp(
    r'<service>([\s\S]*?)</service>',
    multiLine: true,
  ).allMatches(descriptionXml);
  for (final m in services) {
    final block = m.group(1) ?? '';
    if (!block.contains('AVTransport')) continue;
    final ctrlMatch = RegExp(r'<controlURL>([\s\S]*?)</controlURL>')
        .firstMatch(block);
    final ctrl = ctrlMatch?.group(1)?.trim();
    if (ctrl == null || ctrl.isEmpty) continue;
    return _resolve(base: descriptionUrl, ref: ctrl);
  }
  return null;
}

/// 把相对 URL [ref] 解析成相对于 [base] 的绝对 URL。
String _resolve({required String base, required String ref}) {
  if (ref.startsWith('http://') || ref.startsWith('https://')) {
    return ref;
  }
  final baseUri = Uri.parse(base);
  if (ref.startsWith('/')) {
    return '${baseUri.scheme}://${baseUri.authority}$ref';
  }
  // 相对当前路径
  final basePath = baseUri.path.endsWith('/')
      ? baseUri.path
      : baseUri.path.substring(0, baseUri.path.lastIndexOf('/') + 1);
  return '${baseUri.scheme}://${baseUri.authority}$basePath$ref';
}

/// 从 [url] GET 设备 description XML（带 5s 超时）。
/// 失败 / 非 2xx 抛异常。
Future<String> fetchDeviceDescription(
  String url, {
  Duration timeout = const Duration(seconds: 5),
  HttpClient? httpClient,
}) async {
  final client = httpClient ?? HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close().timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException('description fetch failed: ${resp.statusCode}');
    }
    final body = StringBuffer();
    await for (final chunk in resp.transform(const SystemEncoding().decoder)) {
      body.write(chunk);
    }
    return body.toString();
  } finally {
    if (httpClient == null) client.close();
  }
}
