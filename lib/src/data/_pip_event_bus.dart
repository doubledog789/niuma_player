/// PiP EventChannel 进程级单 listener bus，各 backend 共用。
///
/// 直接各自 listen/cancel 有 race：第二次 listen 覆盖 native sink，旧
/// sub.cancel 报 `No active stream to cancel`（不在 await 链上，抓不到）。
/// 故整进程只 listen 一次 root channel，backend 只 sub-listen Dart 侧
/// broadcast，dispose 不向 native 发 cancel。
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'package:niuma_player/src/domain/player_state.dart';

const EventChannel _rawPipEventChannel =
    EventChannel('niuma_player/pip/events');

StreamController<dynamic>? _pipEventBusCtrl;
// 持有 root sub 的引用避免 GC——值 unused 是有意为之。
// ignore: unused_element
StreamSubscription<dynamic>? _pipEventBusRoot;

/// 拿 PiP 事件流——首次调用时 lazy 起 root listener。
Stream<dynamic> pipEventBus() {
  final existing = _pipEventBusCtrl;
  if (existing != null) return existing.stream;
  final ctrl = StreamController<dynamic>.broadcast();
  _pipEventBusCtrl = ctrl;
  _pipEventBusRoot = _rawPipEventChannel.receiveBroadcastStream().listen(
        ctrl.add,
        onError: (Object error, StackTrace stack) =>
            ctrl.addError(error, stack),
      );
  return ctrl.stream;
}

/// 订阅 [pipEventBus] 并把 native map 事件翻成 [NiumaPlayerEvent] 喂给
/// [add]——vp / native 两 backend 共用同一份解析。错误静默（PiP 不可用时
/// root bus 也可能 error）。
StreamSubscription<dynamic> subscribePipEvents(
  void Function(NiumaPlayerEvent event) add,
) {
  return pipEventBus().listen(
    (dynamic data) {
      if (data is! Map) return;
      final event = data['event'];
      if (event is! String) return;
      switch (event) {
        case 'pipStarted':
          add(const PipModeChanged(isInPip: true));
        case 'pipStopped':
          add(const PipModeChanged(isInPip: false));
        case 'playPauseToggle':
          add(const PipRemoteAction(action: 'playPauseToggle'));
      }
    },
    onError: (Object error) {/* 静默忽略 */},
  );
}
