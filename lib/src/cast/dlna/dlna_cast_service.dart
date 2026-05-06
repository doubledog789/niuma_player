import 'dart:async';

import 'package:niuma_player/niuma_player.dart';

import 'avtransport_client.dart';
import 'device_description.dart';
import 'dlna_session.dart';
import 'multicast_lock.dart';
import 'persistent_history.dart';
import 'ssdp_discovery.dart';

/// DLNA 投屏服务——SSDP 发现 + SOAP/AVTransport 远程控制。
///
/// 业务侧 app 启动调 `NiumaCastRegistry.register(DlnaCastService())` 即可启用。
class DlnaCastService extends CastService {
  DlnaCastService({
    SsdpScanner? scanner,
    DlnaHistoryStore? history,
    MulticastLockController? multicastLock,
  })  : _scan = scanner ?? const _RealSsdpScanner(),
        _history = history ?? DlnaHistoryStore(),
        _lock = multicastLock ?? MulticastLockController();

  final SsdpScanner _scan;
  final DlnaHistoryStore _history;
  final MulticastLockController _lock;

  /// 设备 id → location URL 缓存——connect 时拿来构造 controlUrl。
  final Map<String, String> _locationCache = <String, String>{};

  @override
  String get protocolId => 'dlna';

  @override
  Stream<List<CastDevice>> discover({
    Duration timeout = const Duration(seconds: 8),
  }) async* {
    await _lock.acquire();
    try {
      final found = <CastDevice>[];
      final history = await _history.read();
      // 历史命中先吐一发（让 picker 立即看到上次连过的设备占位，
      // 真实扫到了再覆盖）。
      if (history != null) {
        found.add(history.device);
        _locationCache[history.device.id] = history.location;
        yield List<CastDevice>.unmodifiable(found);
      }
      await for (final r in _scan.scan(timeout: timeout)) {
        final uuidMatch = RegExp(r'uuid:([^:]+)').firstMatch(r.usn);
        if (uuidMatch == null) continue;
        final uuid = uuidMatch.group(1)!;
        final id = 'dlna:$uuid';
        final name = r.server ?? Uri.parse(r.location).host;
        final dev = CastDevice(
          id: id,
          name: name,
          protocolId: 'dlna',
        );
        _locationCache[id] = r.location;
        if (!found.any((e) => e.id == dev.id)) {
          found.add(dev);
          yield List<CastDevice>.unmodifiable(found);
        }
      }
    } finally {
      await _lock.release();
    }
  }

  @override
  Future<CastSession> connect(
    CastDevice device,
    NiumaPlayerController controller,
  ) async {
    final location = _locationCache[device.id];
    if (location == null) {
      throw StateError(
          'Device ${device.id} location not in cache—rediscover required');
    }
    // 1. 拉 device description XML，解析 AVTransport controlURL
    final descXml = await fetchDeviceDescription(location);
    final controlUrl = parseAVTransportControlUrl(
      descriptionXml: descXml,
      descriptionUrl: location,
    );
    if (controlUrl == null) {
      throw StateError(
        '设备 ${device.name} 不支持 AVTransport（无法投屏视频）',
      );
    }
    // 2. 用真实 controlURL 起 client
    final client = AVTransportClient(controlUrl: controlUrl);
    final mediaUri = controller.dataSource.uri;
    await client.setMediaUri(mediaUri);
    await client.play();
    unawaited(_history.write(device: device, location: location));
    return DlnaSession(device: device, client: client);
  }
}

/// SSDP 扫描的注入点——让单测注入 fake scanner 而不必碰 dart:io。
abstract class SsdpScanner {
  Stream<SsdpResponse> scan({required Duration timeout});
}

class _RealSsdpScanner implements SsdpScanner {
  const _RealSsdpScanner();
  @override
  Stream<SsdpResponse> scan({required Duration timeout}) =>
      ssdpScan(timeout: timeout);
}
