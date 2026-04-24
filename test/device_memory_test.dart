import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for [DeviceMemory] — the failure-memory store backing the
/// Try-Fail-Remember state machine. The device fingerprint is supplied
/// by the caller so Dart-side tests don't need MethodChannel.
void main() {
  const fingerprint = 'test-fingerprint-abcdef';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('DeviceMemory', () {
    test('default shouldUseIjk returns false when never marked', () async {
      final mem = DeviceMemory();
      expect(await mem.shouldUseIjk(fingerprint), isFalse);
    });

    test('markIjkNeeded flips shouldUseIjk to true', () async {
      final mem = DeviceMemory();
      await mem.markIjkNeeded(fingerprint);
      expect(await mem.shouldUseIjk(fingerprint), isTrue);
    });

    test('markIjkNeeded with TTL expires after the TTL window', () async {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final mem = DeviceMemory(now: () => now);

      await mem.markIjkNeeded(
        fingerprint,
        ttl: const Duration(seconds: 1),
      );

      // Immediately after marking: still hit.
      expect(await mem.shouldUseIjk(fingerprint), isTrue);

      // Advance the clock by 2 seconds -> past the 1 second TTL.
      now = now.add(const Duration(seconds: 2));
      expect(await mem.shouldUseIjk(fingerprint), isFalse);
    });

    test('markIjkNeeded with zero TTL persists (never expires)', () async {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final mem = DeviceMemory(now: () => now);

      await mem.markIjkNeeded(fingerprint); // default TTL = Duration.zero
      now = now.add(const Duration(days: 365));
      expect(await mem.shouldUseIjk(fingerprint), isTrue);
    });

    test('clear() removes the memory for a fingerprint', () async {
      final mem = DeviceMemory();
      await mem.markIjkNeeded(fingerprint);
      expect(await mem.shouldUseIjk(fingerprint), isTrue);

      await mem.clear();
      expect(await mem.shouldUseIjk(fingerprint), isFalse);
    });

    test('different fingerprints are independent', () async {
      final mem = DeviceMemory();
      await mem.markIjkNeeded('device-A');

      expect(await mem.shouldUseIjk('device-A'), isTrue);
      expect(await mem.shouldUseIjk('device-B'), isFalse);
    });
  });
}
