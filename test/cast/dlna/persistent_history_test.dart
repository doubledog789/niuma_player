import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player/src/cast/dlna/persistent_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('write 后 read 拿到同一 entry', () async {
    final store = DlnaHistoryStore();
    const device = CastDevice(
      id: 'dlna:abc',
      name: '客厅小米电视',
      protocolId: 'dlna',
    );
    await store.write(device: device, location: 'http://1.2.3.4/desc.xml');
    final entry = await store.read();
    expect(entry, isNotNull);
    expect(entry!.device.id, 'dlna:abc');
    expect(entry.device.name, '客厅小米电视');
    expect(entry.location, 'http://1.2.3.4/desc.xml');
  });

  test('未写过 read 返 null', () async {
    final store = DlnaHistoryStore();
    expect(await store.read(), isNull);
  });

  test('write 覆盖之前的', () async {
    final store = DlnaHistoryStore();
    await store.write(
      device: const CastDevice(id: 'a', name: 'A', protocolId: 'dlna'),
      location: 'http://a',
    );
    await store.write(
      device: const CastDevice(id: 'b', name: 'B', protocolId: 'dlna'),
      location: 'http://b',
    );
    final entry = await store.read();
    expect(entry!.device.id, 'b');
  });

  test('clear 删历史', () async {
    final store = DlnaHistoryStore();
    await store.write(
      device: const CastDevice(id: 'a', name: 'A', protocolId: 'dlna'),
      location: 'http://a',
    );
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('损坏 JSON 安全降级 null', () async {
    SharedPreferences.setMockInitialValues({
      'niuma_player_dlna.last_device': 'not-json',
    });
    expect(await DlnaHistoryStore().read(), isNull);
  });
}
