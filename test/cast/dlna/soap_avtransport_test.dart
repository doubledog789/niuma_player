import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/cast/dlna/soap_avtransport.dart';

void main() {
  group('SOAP envelope builder', () {
    test('SetAVTransportURI envelope 含 URI', () {
      final body = SoapAVTransport.buildSetAVTransportURI(
        instanceId: 0,
        uri: 'http://example.com/v.mp4',
      );
      expect(body, contains('SetAVTransportURI'));
      expect(body, contains('http://example.com/v.mp4'));
      expect(body, contains('<InstanceID>0</InstanceID>'));
    });

    test('Play envelope', () {
      final body = SoapAVTransport.buildPlay(instanceId: 0);
      expect(body, contains('<u:Play '));
      expect(body, contains('<Speed>1</Speed>'));
    });

    test('Pause envelope', () {
      final body = SoapAVTransport.buildPause(instanceId: 0);
      expect(body, contains('<u:Pause '));
    });

    test('Stop envelope', () {
      final body = SoapAVTransport.buildStop(instanceId: 0);
      expect(body, contains('<u:Stop '));
    });

    test('Seek envelope 含 hh:mm:ss 时间', () {
      final body = SoapAVTransport.buildSeek(
        instanceId: 0,
        position: const Duration(minutes: 1, seconds: 30),
      );
      expect(body, contains('00:01:30'));
      expect(body, contains('<Unit>REL_TIME</Unit>'));
    });
  });

  group('GetPositionInfo response parser', () {
    test('parseRelTime 提取 mm:ss', () {
      const xml = '''<s:Envelope><s:Body>
<u:GetPositionInfoResponse><RelTime>00:02:15</RelTime></u:GetPositionInfoResponse>
</s:Body></s:Envelope>''';
      expect(SoapAVTransport.parseRelTime(xml),
          const Duration(minutes: 2, seconds: 15));
    });

    test('parseRelTime 缺字段返 zero', () {
      expect(SoapAVTransport.parseRelTime('<no/>'), Duration.zero);
    });
  });
}
