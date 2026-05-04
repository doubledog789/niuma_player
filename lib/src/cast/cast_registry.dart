import 'package:flutter/foundation.dart';
import 'cast_service.dart';

/// 投屏协议实现注册表。app 启动时业务调 [register] 注入子包。
class NiumaCastRegistry {
  NiumaCastRegistry._();

  static final List<CastService> _services = <CastService>[];

  /// 注册一个 [CastService]。重复 protocolId 抛 [StateError]。
  static void register(CastService service) {
    if (_services.any((s) => s.protocolId == service.protocolId)) {
      throw StateError(
        'CastService with protocolId="${service.protocolId}" already registered',
      );
    }
    _services.add(service);
  }

  /// 已注册的全部 services。
  static List<CastService> all() => List.unmodifiable(_services);

  /// 按 protocolId 查找。
  static CastService? byProtocolId(String protocolId) {
    for (final s in _services) {
      if (s.protocolId == protocolId) return s;
    }
    return null;
  }

  /// 测试辅助：清空注册。生产代码不要用。
  @visibleForTesting
  static void debugClear() => _services.clear();
}
