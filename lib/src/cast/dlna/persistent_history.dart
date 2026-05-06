import 'dart:convert';

import 'package:niuma_player/niuma_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 历史设备记录。
class DlnaHistoryEntry {
  DlnaHistoryEntry({
    required this.device,
    required this.location,
    DateTime? lastConnectedAt,
  }) : lastConnectedAt = lastConnectedAt ?? DateTime.now();

  final CastDevice device;
  final String location;
  final DateTime lastConnectedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': device.id,
        'name': device.name,
        'protocolId': device.protocolId,
        'location': location,
        'lastConnectedAt': lastConnectedAt.toIso8601String(),
      };

  static DlnaHistoryEntry? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final name = j['name'];
    final protocolId = j['protocolId'];
    final location = j['location'];
    final lastConnectedAt = j['lastConnectedAt'];
    if (id is! String ||
        name is! String ||
        protocolId is! String ||
        location is! String) {
      return null;
    }
    return DlnaHistoryEntry(
      device: CastDevice(id: id, name: name, protocolId: protocolId),
      location: location,
      lastConnectedAt:
          lastConnectedAt is String ? DateTime.tryParse(lastConnectedAt) : null,
    );
  }
}

/// 历史设备存储——SharedPreferences key `niuma_player_dlna.last_device`。
/// 只留最近 1 台。
class DlnaHistoryStore {
  static const _key = 'niuma_player_dlna.last_device';

  /// 读历史。失败 / 缺记录返 null。
  Future<DlnaHistoryEntry?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      return DlnaHistoryEntry.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  /// 写历史（覆盖之前的）。失败静默。
  Future<void> write({
    required CastDevice device,
    required String location,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entry = DlnaHistoryEntry(device: device, location: location);
      await prefs.setString(_key, jsonEncode(entry.toJson()));
    } catch (_) {}
  }

  /// 清空历史。
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
