import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/cast/cast_device.dart';
import 'package:niuma_player/src/cast/cast_state.dart';

void main() {
  group('CastDevice', () {
    test('相同 id 视为相等', () {
      const a = CastDevice(
        id: 'dlna:001',
        name: '客厅小米电视',
        protocolId: 'dlna',
      );
      const b = CastDevice(
        id: 'dlna:001',
        name: '其他名字',
        protocolId: 'dlna',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('不同 id 不等', () {
      const a = CastDevice(id: 'a', name: 'A', protocolId: 'dlna');
      const b = CastDevice(id: 'b', name: 'B', protocolId: 'dlna');
      expect(a, isNot(equals(b)));
    });

    test('默认 icon 是 Icons.tv', () {
      const d = CastDevice(id: 'x', name: 'X', protocolId: 'dlna');
      expect(d.icon, Icons.tv);
    });
  });

  group('CastConnectionState / CastEndReason', () {
    test('枚举完整', () {
      expect(CastConnectionState.values, [
        CastConnectionState.idle,
        CastConnectionState.discovering,
        CastConnectionState.connecting,
        CastConnectionState.connected,
        CastConnectionState.error,
      ]);
      expect(CastEndReason.values, [
        CastEndReason.userCancelled,
        CastEndReason.networkError,
        CastEndReason.deviceLost,
        CastEndReason.timeout,
      ]);
    });
  });
}
