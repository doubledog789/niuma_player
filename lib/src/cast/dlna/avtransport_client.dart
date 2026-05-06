import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:niuma_player/src/cast/dlna/soap_avtransport.dart';

/// 抽象 HTTP POST 接口，让 AVTransportClient 在测试时注入 Mock，
/// 生产用 [_RealSoapHttp]。
abstract class SoapHttp {
  Future<SoapHttpResponse> post(
    String url,
    Map<String, String> headers,
    String body,
  );
}

/// SOAP HTTP 响应。
class SoapHttpResponse {
  SoapHttpResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

class _RealSoapHttp implements SoapHttp {
  @override
  Future<SoapHttpResponse> post(
      String url, Map<String, String> headers, String body) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(url));
      headers.forEach(req.headers.set);
      req.add(body.codeUnits);
      final resp =
          await req.close().timeout(const Duration(seconds: 5));
      final data = await resp.transform(const Utf8Decoder()).join();
      return SoapHttpResponse(resp.statusCode, data);
    } finally {
      client.close();
    }
  }
}

/// AVTransport SOAP 调用失败抛出。
class AVTransportException implements Exception {
  AVTransportException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'AVTransportException($statusCode): $body';
}

/// AVTransport HTTP 客户端——封装 SOAP request 构造 + 响应处理。
class AVTransportClient {
  AVTransportClient({
    required this.controlUrl,
    SoapHttp? http,
    this.instanceId = 0,
    this.timeout = const Duration(seconds: 10),
  }) : _http = http ?? _RealSoapHttp();

  final String controlUrl;
  final int instanceId;
  final Duration timeout;
  final SoapHttp _http;

  Future<String> _call(String soapAction, String body) async {
    final headers = {
      'Content-Type': 'text/xml; charset="utf-8"',
      'SOAPACTION':
          '"urn:schemas-upnp-org:service:AVTransport:1#$soapAction"',
    };
    try {
      final resp =
          await _http.post(controlUrl, headers, body).timeout(timeout);
      if (resp.statusCode != 200) {
        throw AVTransportException(resp.statusCode, resp.body);
      }
      return resp.body;
    } on TimeoutException catch (e) {
      throw AVTransportException(
          0, 'timeout after ${timeout.inSeconds}s: $e');
    }
  }

  Future<void> setMediaUri(String uri) => _call(
        'SetAVTransportURI',
        SoapAVTransport.buildSetAVTransportURI(
          instanceId: instanceId,
          uri: uri,
        ),
      );

  Future<void> play() =>
      _call('Play', SoapAVTransport.buildPlay(instanceId: instanceId));

  Future<void> pause() =>
      _call('Pause', SoapAVTransport.buildPause(instanceId: instanceId));

  Future<void> stop() =>
      _call('Stop', SoapAVTransport.buildStop(instanceId: instanceId));

  Future<void> seek(Duration position) => _call(
        'Seek',
        SoapAVTransport.buildSeek(
          instanceId: instanceId,
          position: position,
        ),
      );

  Future<Duration> getPosition() async {
    final resp = await _call(
      'GetPositionInfo',
      SoapAVTransport.buildGetPositionInfo(instanceId: instanceId),
    );
    return SoapAVTransport.parseRelTime(resp);
  }
}
