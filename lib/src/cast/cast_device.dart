import 'package:meta/meta.dart' show immutable;

/// 一台被发现的投屏目标设备。
@immutable
class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.protocolId,
  });

  /// 全局唯一 id。约定格式：`<protocolId>:<协议内设备指纹>`，
  /// 例如 `dlna:uuid:abc-123` / `airplay:Apple-TV-XYZ`。
  final String id;

  /// 用户可见名："客厅小米电视" / "Apple TV"。
  final String name;

  /// 协议 id：`dlna` / `airplay`。
  final String protocolId;

  @override
  bool operator ==(Object other) =>
      other is CastDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'CastDevice(id: $id, name: $name, protocolId: $protocolId)';
}
