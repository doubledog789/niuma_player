import 'package:flutter/foundation.dart';
import 'cast_device.dart';
import 'cast_state.dart';

/// 一次投屏会话——connect 成功后由 CastService 返回。
abstract class CastSession {
  /// 关联的设备。
  CastDevice get device;

  /// 连接状态。connect 后通常立即 connected；网络问题会切到 error，
  /// 由 controller 兜底处理。
  ValueListenable<CastConnectionState> get state;

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// 主动断开。controller dispose 时也会调。
  Future<void> disconnect();
}
