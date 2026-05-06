import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/cast/dlna/avtransport_client.dart';

class _SlowMockHttp implements SoapHttp {
  @override
  Future<SoapHttpResponse> post(
      String url, Map<String, String> headers, String body) async {
    // 永不返回——模拟 hang
    final completer = Completer<SoapHttpResponse>();
    return completer.future;
  }
}

class _MockHttp implements SoapHttp {
  String? lastUrl;
  String? lastBody;
  Map<String, String>? lastHeaders;
  int statusCode = 200;
  String responseBody =
      '<s:Envelope><s:Body><u:PlayResponse/></s:Body></s:Envelope>';

  @override
  Future<SoapHttpResponse> post(
      String url, Map<String, String> headers, String body) async {
    lastUrl = url;
    lastBody = body;
    lastHeaders = headers;
    return SoapHttpResponse(statusCode, responseBody);
  }
}

void main() {
  test('play 调 controlUrl 并发 SOAP body', () async {
    final http = _MockHttp();
    final client = AVTransportClient(
      controlUrl: 'http://192.168.1.10:49152/AVTransport/control',
      http: http,
    );
    await client.play();
    expect(http.lastUrl, 'http://192.168.1.10:49152/AVTransport/control');
    expect(http.lastBody, contains('<u:Play '));
    expect(http.lastBody, contains('<Speed>1</Speed>'));
    expect(http.lastHeaders!['SOAPACTION'],
        contains('AVTransport:1#Play'));
  });

  test('500 响应抛 AVTransportException', () async {
    final http = _MockHttp()..statusCode = 500;
    final client = AVTransportClient(
      controlUrl: 'http://x/control',
      http: http,
    );
    expect(() => client.play(), throwsA(isA<AVTransportException>()));
  });

  test('请求 timeout 抛 AVTransportException', () async {
    final http = _SlowMockHttp();
    final client = AVTransportClient(
      controlUrl: 'http://x/control',
      http: http,
      timeout: const Duration(milliseconds: 100),
    );
    expect(
      () => client.play(),
      throwsA(isA<AVTransportException>()),
    );
  });

  test('getPosition 解析 RelTime', () async {
    final http = _MockHttp()
      ..responseBody = '''<s:Envelope><s:Body>
<u:GetPositionInfoResponse><RelTime>00:01:23</RelTime></u:GetPositionInfoResponse>
</s:Body></s:Envelope>''';
    final client = AVTransportClient(
      controlUrl: 'http://x/control',
      http: http,
    );
    expect(await client.getPosition(),
        const Duration(minutes: 1, seconds: 23));
  });
}
