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

  group('NiumaPlayerController play/pause/seekTo cast 透传', () {
    test('castSession=null → play 调 backend', () async {
      final c = FakeNiumaPlayerController();
      await c.play();
      expect(c.playCount, 1);
    });

    test('castSession 非 null → play 调 session.play 不调 backend', () async {
      final c = FakeNiumaPlayerController();
      final s = _CountingFakeSession();
      c.debugSetCastSession(s);
      await c.play();
      expect(s.playCalled, 1);
      expect(c.playCount, 0, reason: '投屏时本地 backend 不调');
    });

    test('castSession 非 null → pause / seekTo 透传', () async {
      final c = FakeNiumaPlayerController();
      final s = _CountingFakeSession();
      c.debugSetCastSession(s);
      await c.pause();
      await c.seekTo(const Duration(seconds: 30));
      expect(s.pauseCalled, 1);
      expect(s.lastSeek, const Duration(seconds: 30));
      expect(c.pauseCount, 0);
      expect(c.lastSeek, isNull);
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
  @override
  Future<Duration> getPosition() async => Duration.zero;
}

class _CountingFakeSession implements CastSession {
  int playCalled = 0;
  int pauseCalled = 0;
  Duration? lastSeek;
  int disconnectCalled = 0;
  Duration currentPosition = Duration.zero;

  @override
  CastDevice get device => const CastDevice(id: 'x', name: 'X', protocolId: 'dlna');
  @override
  ValueListenable<CastConnectionState> get state =>
      ValueNotifier(CastConnectionState.connected);
  @override
  Future<void> play() async => playCalled++;
  @override
  Future<void> pause() async => pauseCalled++;
  @override
  Future<void> seek(Duration p) async => lastSeek = p;
  @override
  Future<void> disconnect() async => disconnectCalled++;
  @override
  Future<Duration> getPosition() async => currentPosition;
}
