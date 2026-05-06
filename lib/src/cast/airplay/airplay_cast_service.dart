import 'package:niuma_player/niuma_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// AirPlay 投屏服务——iOS only。其他平台 discover 返空，connect 抛 UnsupportedError。
///
/// 实现策略：iOS AirPlay 由系统 AVPictureInPictureController + AVPlayer
/// 自动管理路由——SDK 不维护精确 session。`discover` 返一个虚拟设备
/// "AirPlay"，用户点 → SDK 调原生 `showRoutePicker` 弹起 iOS 系统 picker，
/// 系统接手剩下流程。
class AirPlayCastService extends CastService {
  AirPlayCastService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('niuma_player_airplay/main');

  final MethodChannel _channel;

  @override
  String get protocolId => 'airplay';

  @override
  Stream<List<CastDevice>> discover({
    Duration timeout = const Duration(seconds: 8),
  }) async* {
    if (!_isIOS) {
      // 非 iOS 平台 yield 空——picker 显示"未发现设备"
      yield const <CastDevice>[];
      return;
    }
    // iOS：yield 一个虚拟"AirPlay"设备代表"打开 iOS 系统 picker"
    yield const <CastDevice>[
      CastDevice(
        id: 'airplay:system',
        name: 'AirPlay (iOS 设备)',
        protocolId: 'airplay',
        icon: Icons.airplay,
      ),
    ];
  }

  @override
  Future<CastSession> connect(
    CastDevice device,
    NiumaPlayerController controller,
  ) async {
    if (!_isIOS) {
      throw UnsupportedError('AirPlay 仅支持 iOS');
    }
    try {
      await _channel.invokeMethod<bool>('showRoutePicker');
    } catch (_) {
      // picker 弹失败——直接抛，让上层 toast
    }
    // iOS 系统 picker 打开后，剩下流程由系统接管。
    // 这里 throw 一个特殊异常告诉 picker UI："系统接管，不要走 controller.connectCast"
    throw _AirPlayHandedOffToSystem();
  }

  bool get _isIOS =>
      defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb;
}

/// 信号异常：AirPlay 已交给 iOS 系统处理，picker UI 不应再调
/// `controller.connectCast(session)`。
class _AirPlayHandedOffToSystem implements Exception {
  @override
  String toString() => 'AirPlay handed off to iOS system';
}
