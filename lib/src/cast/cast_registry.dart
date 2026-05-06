import 'package:flutter/foundation.dart';
import 'package:niuma_player/src/cast/airplay_cast_service.dart';
import 'package:niuma_player/src/cast/cast_service.dart';
import 'package:niuma_player/src/cast/dlna/dlna_cast_service.dart';

/// 投屏协议实现注册表。
///
/// **0.x 起 SDK 自动 register DLNA + AirPlay**——首次访问 [all] / [byProtocolId]
/// 时 lazy 把 [DlnaCastService] 和 [AirPlayCastService] 加进来，业务方
/// 0 配置就能用。仍可调 [register] 加自家协议（如 Chromecast）。
///
/// 业务想替换默认实现（自家 DLNA fork 等），可以：
/// 1. 在 app `main()` 第一句调 [register] 注入自家 service
/// 2. lazy default 看到该 protocolId 已存在不会重复注册
class NiumaCastRegistry {
  NiumaCastRegistry._();

  static final List<CastService> _services = <CastService>[];
  static bool _defaultsLoaded = false;

  /// 首次访问时填入 SDK 内置 default services。重复 protocolId 不覆盖
  /// 已注册的，让业务方先调 [register] 注入自家实现就能赢。
  static void _ensureDefaultsLoaded() {
    if (_defaultsLoaded) return;
    _defaultsLoaded = true;
    if (!_services.any((s) => s.protocolId == 'dlna')) {
      _services.add(DlnaCastService());
    }
    if (!_services.any((s) => s.protocolId == 'airplay')) {
      _services.add(AirPlayCastService());
    }
  }

  /// 注册一个 [CastService]。重复 protocolId 抛 [StateError]。
  ///
  /// 业务想替换 SDK 默认 DLNA / AirPlay：在 app `main()` 第一句调即可——
  /// lazy default load 会跳过已注册的 protocolId。
  static void register(CastService service) {
    if (_services.any((s) => s.protocolId == service.protocolId)) {
      throw StateError(
        'CastService with protocolId="${service.protocolId}" already registered',
      );
    }
    _services.add(service);
  }

  /// 已注册的全部 services（含 SDK 内置 DLNA + AirPlay）。
  static List<CastService> all() {
    _ensureDefaultsLoaded();
    return List.unmodifiable(_services);
  }

  /// 按 protocolId 查找。
  static CastService? byProtocolId(String protocolId) {
    _ensureDefaultsLoaded();
    for (final s in _services) {
      if (s.protocolId == protocolId) return s;
    }
    return null;
  }

  /// 测试辅助：清空注册（含 default loaded 标志）。生产代码不要用。
  @visibleForTesting
  static void debugClear() {
    _services.clear();
    _defaultsLoaded = false;
  }
}
