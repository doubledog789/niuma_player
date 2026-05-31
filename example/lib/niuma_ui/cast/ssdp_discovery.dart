import 'dart:async';
import 'dart:io';

/// SSDP 单播响应解析结果。
class SsdpResponse {
  SsdpResponse({required this.location, required this.usn, this.server, this.st});
  final String location;
  final String usn;
  final String? server;
  final String? st;
}

/// 解析 SSDP 单播响应。返 null 表非有效响应（缺少必要字段）。
SsdpResponse? parseSsdpResponse(String raw) {
  final lines = raw.split(RegExp(r'\r?\n'));
  if (lines.isEmpty || !lines[0].startsWith('HTTP/1.1 200')) return null;
  String? location;
  String? usn;
  String? server;
  String? st;
  for (final line in lines.skip(1)) {
    final idx = line.indexOf(':');
    if (idx < 0) continue;
    final k = line.substring(0, idx).trim().toUpperCase();
    final v = line.substring(idx + 1).trim();
    switch (k) {
      case 'LOCATION':
        location = v;
        break;
      case 'USN':
        usn = v;
        break;
      case 'SERVER':
        server = v;
        break;
      case 'ST':
        st = v;
        break;
    }
  }
  if (location == null || usn == null) return null;
  return SsdpResponse(location: location, usn: usn, server: server, st: st);
}

/// 判断 SSDP 响应是否是 UPnP MediaRenderer 设备。
bool isMediaRenderer(SsdpResponse r) =>
    r.st?.contains('MediaRenderer') ?? false;

/// 构造 SSDP M-SEARCH 报文。MX = MediaRenderer 响应等待最大秒数（建议 3-5）。
String buildSsdpMSearch({int mxSeconds = 3}) {
  return 'M-SEARCH * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: $mxSeconds\r\n'
      'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
      '\r\n';
}

/// 真实 SSDP 多播扫描——发送 M-SEARCH，监听响应 [timeout] 秒。
/// stream 吐每条解析成功的 [SsdpResponse]。
///
/// **网络层失败静默结束**：iOS 真机上 SSDP 多播会因 (1) `Info.plist`
/// 缺 `NSLocalNetworkUsageDescription` / `NSBonjourServices`、(2) 缺
/// `com.apple.developer.networking.multicast` entitlement（免费 Apple ID
/// 无法签）、(3) 设备未连 Wi-Fi 等原因撞 `SocketException` (errno 65 /
/// `EHOSTUNREACH`)。这是平台 + 账号限制不是 SDK bug，源头 try-catch
/// 后让 stream 正常结束（无设备发现）——业务侧的 picker 自然显示"未找到
/// 投屏设备"，不应该把 unhandled exception 冒到 zone 顶污染 console。
Stream<SsdpResponse> ssdpScan({
  Duration timeout = const Duration(seconds: 8),
}) async* {
  RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final dst = InternetAddress('239.255.255.250');
    final mxSecs = timeout.inSeconds.clamp(1, 5);
    final msg = buildSsdpMSearch(mxSeconds: mxSecs);
    socket.send(msg.codeUnits, dst, 1900);
  } on SocketException {
    return;
  }
  final controller = StreamController<SsdpResponse>();
  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    final raw = String.fromCharCodes(dg.data);
    final parsed = parseSsdpResponse(raw);
    if (parsed != null && isMediaRenderer(parsed)) controller.add(parsed);
  });
  Timer(timeout, () {
    sub.cancel();
    socket.close();
    controller.close();
  });
  yield* controller.stream;
}
