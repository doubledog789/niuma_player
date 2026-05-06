import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/cast/dlna/device_description.dart';

void main() {
  group('parseAVTransportControlUrl', () {
    const baseUrl = 'http://192.168.1.10:49152/desc.xml';

    test('提取 AVTransport 的 controlURL（相对路径 → 绝对）', () {
      const xml = '''
<root>
  <device>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/RC/Control</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/AVT/Control</controlURL>
      </service>
    </serviceList>
  </device>
</root>''';
      final url = parseAVTransportControlUrl(
        descriptionXml: xml,
        descriptionUrl: baseUrl,
      );
      expect(url, 'http://192.168.1.10:49152/AVT/Control');
    });

    test('controlURL 是绝对 URL → 直接返', () {
      const xml = '''
<root><device><serviceList>
  <service>
    <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
    <controlURL>http://other.host:8080/cmd</controlURL>
  </service>
</serviceList></device></root>''';
      final url = parseAVTransportControlUrl(
        descriptionXml: xml,
        descriptionUrl: baseUrl,
      );
      expect(url, 'http://other.host:8080/cmd');
    });

    test('controlURL 是相对当前路径', () {
      const xml = '''
<root><device><serviceList>
  <service>
    <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
    <controlURL>cmd</controlURL>
  </service>
</serviceList></device></root>''';
      final url = parseAVTransportControlUrl(
        descriptionXml: xml,
        descriptionUrl: 'http://1.2.3.4:49152/some/path/desc.xml',
      );
      expect(url, 'http://1.2.3.4:49152/some/path/cmd');
    });

    test('XML 没 AVTransport service → 返 null', () {
      const xml = '''
<root><device><serviceList>
  <service>
    <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
    <controlURL>/RC/Control</controlURL>
  </service>
</serviceList></device></root>''';
      final url = parseAVTransportControlUrl(
        descriptionXml: xml,
        descriptionUrl: baseUrl,
      );
      expect(url, isNull);
    });
  });
}
