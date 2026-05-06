import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/cast/dlna/ssdp_discovery.dart';

void main() {
  group('parseSsdpResponse', () {
    test('解析正常响应', () {
      const raw = '''HTTP/1.1 200 OK\r
LOCATION: http://192.168.1.10:49152/desc.xml\r
SERVER: Linux/4.4 UPnP/1.0 GUPnP/1.0.5\r
ST: urn:schemas-upnp-org:device:MediaRenderer:1\r
USN: uuid:abc-123::urn:schemas-upnp-org:device:MediaRenderer:1\r
''';
      final r = parseSsdpResponse(raw);
      expect(r, isNotNull);
      expect(r!.location, 'http://192.168.1.10:49152/desc.xml');
      expect(r.usn, contains('uuid:abc-123'));
      expect(r.st, 'urn:schemas-upnp-org:device:MediaRenderer:1');
    });

    test('非 200 返 null', () {
      const raw = 'HTTP/1.1 404 Not Found\r\n';
      expect(parseSsdpResponse(raw), isNull);
    });

    test('缺 LOCATION 返 null', () {
      const raw = 'HTTP/1.1 200 OK\r\nUSN: uuid:x\r\n';
      expect(parseSsdpResponse(raw), isNull);
    });

    test('缺 USN 返 null', () {
      const raw = 'HTTP/1.1 200 OK\r\nLOCATION: http://x/desc.xml\r\n';
      expect(parseSsdpResponse(raw), isNull);
    });

    test('ST 字段被正确解析', () {
      const raw = 'HTTP/1.1 200 OK\r\n'
          'LOCATION: http://192.168.1.1:1234/desc.xml\r\n'
          'USN: uuid:xyz::urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n';
      final r = parseSsdpResponse(raw);
      expect(r, isNotNull);
      expect(r!.st, 'urn:schemas-upnp-org:device:MediaRenderer:1');
    });
  });

  group('isMediaRenderer', () {
    test('ST 含 MediaRenderer → true', () {
      final r = SsdpResponse(
        location: 'http://x/desc.xml',
        usn: 'uuid:x',
        st: 'urn:schemas-upnp-org:device:MediaRenderer:1',
      );
      expect(isMediaRenderer(r), isTrue);
    });

    test('ST 不含 MediaRenderer → false', () {
      final r = SsdpResponse(
        location: 'http://x/desc.xml',
        usn: 'uuid:x',
        st: 'urn:schemas-upnp-org:device:InternetGatewayDevice:1',
      );
      expect(isMediaRenderer(r), isFalse);
    });

    test('ST 为 null → false', () {
      final r = SsdpResponse(
        location: 'http://x/desc.xml',
        usn: 'uuid:x',
      );
      expect(isMediaRenderer(r), isFalse);
    });
  });

  group('buildSsdpMSearch', () {
    test('M-SEARCH 报文符合 UPnP 1.0 规范', () {
      final msg = buildSsdpMSearch(mxSeconds: 3);
      expect(msg, contains('M-SEARCH * HTTP/1.1'));
      expect(msg, contains('HOST: 239.255.255.250:1900'));
      expect(msg, contains('MAN: "ssdp:discover"'));
      expect(msg, contains('MX: 3'));
      expect(msg, contains('ST: urn:schemas-upnp-org:device:MediaRenderer:1'));
    });
  });
}
