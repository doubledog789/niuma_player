import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/cast/dlna/dlna_cast_service.dart';
import 'package:niuma_player/src/cast/dlna/multicast_lock.dart';
import 'package:niuma_player/src/cast/dlna/persistent_history.dart';
import 'package:niuma_player/src/cast/dlna/ssdp_discovery.dart';

class _FakeScanner implements SsdpScanner {
  _FakeScanner(this.responses);
  final List<SsdpResponse> responses;
  @override
  Stream<SsdpResponse> scan({required Duration timeout}) async* {
    for (final r in responses) {
      yield r;
    }
  }
}

class _FakeHistory implements DlnaHistoryStore {
  DlnaHistoryEntry? entry;
  CastDevice? lastWrittenDevice;
  String? lastWrittenLocation;
  @override
  Future<DlnaHistoryEntry?> read() async => entry;
  @override
  Future<void> write({required CastDevice device, required String location}) async {
    lastWrittenDevice = device;
    lastWrittenLocation = location;
    entry = DlnaHistoryEntry(device: device, location: location);
  }
  @override
  Future<void> clear() async => entry = null;
}

class _FakeMulticastLock implements MulticastLockController {
  int acquireCalled = 0;
  int releaseCalled = 0;
  @override
  Future<void> acquire() async => acquireCalled++;
  @override
  Future<void> release() async => releaseCalled++;
}

void main() {
  test('protocolId 是 dlna', () {
    expect(DlnaCastService().protocolId, 'dlna');
  });

  test('discover 扫到设备 → yield 累计列表', () async {
    final scanner = _FakeScanner([
      SsdpResponse(
        location: 'http://192.168.1.10:49152/desc.xml',
        usn: 'uuid:abc-123::urn:schemas-upnp-org:device:MediaRenderer:1',
        server: '客厅小米电视',
      ),
      SsdpResponse(
        location: 'http://192.168.1.20:49152/desc.xml',
        usn: 'uuid:def-456::urn:schemas-upnp-org:device:MediaRenderer:1',
        server: '卧室海信',
      ),
    ]);
    final svc = DlnaCastService(
      scanner: scanner,
      history: _FakeHistory(),
      multicastLock: _FakeMulticastLock(),
    );
    final batches = await svc.discover().toList();
    expect(batches.length, 2);
    expect(batches.last.length, 2);
    expect(batches.last.map((d) => d.id),
        containsAll(['dlna:abc-123', 'dlna:def-456']));
  });

  test('discover 期间 acquire/release multicast lock', () async {
    final lock = _FakeMulticastLock();
    final svc = DlnaCastService(
      scanner: _FakeScanner(const []),
      history: _FakeHistory(),
      multicastLock: lock,
    );
    await svc.discover().toList();
    expect(lock.acquireCalled, 1);
    expect(lock.releaseCalled, 1);
  });

  test('历史设备先吐一发（占位）', () async {
    const device = CastDevice(
      id: 'dlna:hist-1',
      name: '历史小米电视',
      protocolId: 'dlna',
    );
    final history = _FakeHistory()
      ..entry = DlnaHistoryEntry(
        device: device,
        location: 'http://192.168.1.10:49152/desc.xml',
      );
    final svc = DlnaCastService(
      scanner: _FakeScanner(const []),
      history: history,
      multicastLock: _FakeMulticastLock(),
    );
    final batches = await svc.discover().toList();
    expect(batches.first.first.id, 'dlna:hist-1');
  });
}
