import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

import 'controls/fake_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NiumaPlayerController.castSession', () {
    test('默认 null', () {
      final c = FakeNiumaPlayerController();
      expect(c.castSession.value, isNull);
    });

    test('debugSetCastSession 改值并 notify', () {
      final c = FakeNiumaPlayerController();
      var fired = 0;
      c.castSession.addListener(() => fired++);
      c.debugSetCastSession(_FakeSession());
      expect(c.castSession.value, isNotNull);
      expect(fired, 1);
      c.debugSetCastSession(null);
      expect(c.castSession.value, isNull);
      expect(fired, 2);
    });
  });
}

class _FakeSession implements CastSession {
  @override
  CastDevice get device => const CastDevice(id: 'x', name: 'X', protocolId: 'dlna');
  @override
  ValueListenable<CastConnectionState> get state =>
      ValueNotifier(CastConnectionState.connected);
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration p) async {}
  @override
  Future<void> disconnect() async {}
}
