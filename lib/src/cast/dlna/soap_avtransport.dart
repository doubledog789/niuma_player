/// SOAP envelope builder + parser，用于 UPnP/AVTransport:1 服务。
class SoapAVTransport {
  SoapAVTransport._();

  static const _ns = 'urn:schemas-upnp-org:service:AVTransport:1';

  static String _envelope(String body) =>
      '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
      ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body>$body</s:Body></s:Envelope>';

  static String buildSetAVTransportURI({
    required int instanceId,
    required String uri,
    String metadata = '',
  }) {
    final esc = _escape(uri);
    final metaEsc = _escape(metadata);
    return _envelope(
      '<u:SetAVTransportURI xmlns:u="$_ns">'
      '<InstanceID>$instanceId</InstanceID>'
      '<CurrentURI>$esc</CurrentURI>'
      '<CurrentURIMetaData>$metaEsc</CurrentURIMetaData>'
      '</u:SetAVTransportURI>',
    );
  }

  static String buildPlay({required int instanceId, int speed = 1}) =>
      _envelope(
        '<u:Play xmlns:u="$_ns">'
        '<InstanceID>$instanceId</InstanceID>'
        '<Speed>$speed</Speed>'
        '</u:Play>',
      );

  static String buildPause({required int instanceId}) => _envelope(
        '<u:Pause xmlns:u="$_ns">'
        '<InstanceID>$instanceId</InstanceID>'
        '</u:Pause>',
      );

  static String buildStop({required int instanceId}) => _envelope(
        '<u:Stop xmlns:u="$_ns">'
        '<InstanceID>$instanceId</InstanceID>'
        '</u:Stop>',
      );

  static String buildSeek({
    required int instanceId,
    required Duration position,
  }) {
    final hh = position.inHours.toString().padLeft(2, '0');
    final mm = (position.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (position.inSeconds % 60).toString().padLeft(2, '0');
    return _envelope(
      '<u:Seek xmlns:u="$_ns">'
      '<InstanceID>$instanceId</InstanceID>'
      '<Unit>REL_TIME</Unit>'
      '<Target>$hh:$mm:$ss</Target>'
      '</u:Seek>',
    );
  }

  static String buildGetPositionInfo({required int instanceId}) => _envelope(
        '<u:GetPositionInfo xmlns:u="$_ns">'
        '<InstanceID>$instanceId</InstanceID>'
        '</u:GetPositionInfo>',
      );

  /// 解析 GetPositionInfoResponse 的 RelTime 字段（hh:mm:ss）。
  /// 缺字段返 [Duration.zero]。
  static Duration parseRelTime(String responseXml) {
    final m = RegExp(r'<RelTime>(\d+):(\d+):(\d+)</RelTime>')
        .firstMatch(responseXml);
    if (m == null) return Duration.zero;
    return Duration(
      hours: int.parse(m.group(1)!),
      minutes: int.parse(m.group(2)!),
      seconds: int.parse(m.group(3)!),
    );
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
