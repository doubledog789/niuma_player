import 'package:niuma_player/niuma_player.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:niuma_player/src/cast/dlna/avtransport_client.dart';

/// 一次 DLNA 投屏会话——把 [AVTransportClient] 包成 SDK 通用 [CastSession]。
///
/// 实现策略：所有命令直接转发到 client；不做心跳监控（MVP）。
/// 失败 / 设备失联由调用方（NiumaCastPicker 的 connect 流程）通过 catch
/// 异常后调 `controller.disconnectCast(reason: networkError)` 处理。
class DlnaSession implements CastSession {
  DlnaSession({required this.device, required this.client});

  @override
  final CastDevice device;
  final AVTransportClient client;

  final ValueNotifier<CastConnectionState> _state =
      ValueNotifier<CastConnectionState>(CastConnectionState.connected);
  bool _disposed = false;

  @override
  ValueListenable<CastConnectionState> get state => _state;

  @override
  Future<void> play() => client.play();

  @override
  Future<void> pause() => client.pause();

  @override
  Future<void> seek(Duration position) => client.seek(position);

  @override
  Future<Duration> getPosition() => client.getPosition();

  @override
  Future<void> disconnect() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await client.stop().timeout(const Duration(seconds: 2));
    } catch (_) {
      // 忽略——即使 stop 失败，dispose 也要继续
    }
    _state.value = CastConnectionState.idle;
    _state.dispose();
  }
}
