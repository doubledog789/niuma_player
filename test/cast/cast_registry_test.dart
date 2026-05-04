import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

class _FakeService extends CastService {
  _FakeService(this.protocolId);
  @override
  final String protocolId;
  @override
  Stream<List<CastDevice>> discover({Duration timeout = const Duration(seconds: 8)}) =>
      const Stream<List<CastDevice>>.empty();
  @override
  Future<CastSession> connect(CastDevice device, NiumaPlayerController c) =>
      throw UnimplementedError();
}

void main() {
  group('NiumaCastRegistry', () {
    setUp(NiumaCastRegistry.debugClear);

    test('register / all', () {
      NiumaCastRegistry.register(_FakeService('dlna'));
      NiumaCastRegistry.register(_FakeService('airplay'));
      expect(NiumaCastRegistry.all().length, 2);
    });

    test('byProtocolId', () {
      final s = _FakeService('dlna');
      NiumaCastRegistry.register(s);
      expect(NiumaCastRegistry.byProtocolId('dlna'), same(s));
      expect(NiumaCastRegistry.byProtocolId('unknown'), isNull);
    });

    test('重复 protocolId 抛 StateError', () {
      NiumaCastRegistry.register(_FakeService('dlna'));
      expect(
        () => NiumaCastRegistry.register(_FakeService('dlna')),
        throwsStateError,
      );
    });
  });
}
