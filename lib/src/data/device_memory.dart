import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent "this device needs IJK" memory, keyed by device fingerprint.
///
/// Stored as JSON under `niuma_player.ijk_needed.<fingerprint>`:
/// ```json
/// { "needed": true, "expiresAt": 1713945600000 | null }
/// ```
/// `expiresAt` is epoch milliseconds; `null` means forever.
class DeviceMemory {
  DeviceMemory({
    SharedPreferences? prefs,
    DateTime Function()? now,
  })  : _prefsOverride = prefs,
        _now = now ?? DateTime.now;

  final SharedPreferences? _prefsOverride;
  final DateTime Function() _now;

  static const String _prefix = 'niuma_player.ijk_needed.';

  Future<SharedPreferences> _prefs() async {
    return _prefsOverride ?? await SharedPreferences.getInstance();
  }

  String _key(String fingerprint) => '$_prefix$fingerprint';

  /// Returns true if we previously recorded that [fingerprint] needs IJK and
  /// the record hasn't expired.
  Future<bool> shouldUseIjk(String fingerprint) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key(fingerprint));
    if (raw == null) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final needed = decoded['needed'] == true;
      if (!needed) return false;
      final expiresAt = decoded['expiresAt'];
      if (expiresAt == null) return true;
      if (expiresAt is! int) return true;
      final nowMs = _now().millisecondsSinceEpoch;
      if (nowMs >= expiresAt) {
        // Expired → clean up eagerly so we only pay the read cost once.
        await prefs.remove(_key(fingerprint));
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Records that [fingerprint] needs IJK. If [ttl] is null or zero, the
  /// record is permanent; otherwise it expires after [ttl] from now.
  Future<void> markIjkNeeded(
    String fingerprint, {
    Duration? ttl,
  }) async {
    final prefs = await _prefs();
    final hasTtl = ttl != null && ttl > Duration.zero;
    final expiresAt = hasTtl
        ? _now().millisecondsSinceEpoch + ttl.inMilliseconds
        : null;
    final payload = jsonEncode(<String, dynamic>{
      'needed': true,
      'expiresAt': expiresAt,
    });
    await prefs.setString(_key(fingerprint), payload);
  }

  /// Clears all niuma_player memory entries (useful for debug UI).
  Future<void> clear() async {
    final prefs = await _prefs();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
