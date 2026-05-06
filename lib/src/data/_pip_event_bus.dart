/// PiP EventChannel 进程级单 listener bus——VideoPlayerBackend +
/// NativeBackend 共用，避开 Flutter engine 的 EventChannel 单 listener
/// 模型在 controller 复用时 cancel 报错。
///
/// 直接 `EventChannel('niuma_player/pip/events').receiveBroadcastStream()
/// .listen(...)` + sub.cancel 的 race：第二次 listen 自动覆盖 native 端
/// `_currentSink`，旧 sub.cancel 来时 native 端 sink 已被前一次清空 →
/// iOS 报 `PlatformException(error, No active stream to cancel)` 从
/// StreamController.onCancel 内部 zone 抛出（**不在 await 链上**、
/// try-catch 抓不到）。Android engine 行为类似。
///
/// 解法：整个进程只 listen 一次 root EventChannel；每个 backend 实例
/// sub-listen 这条 Dart-side broadcast。backend dispose 时 cancel 的是
/// Dart 内 sub，**不向 native 发 cancel 消息**——根本不会触发 race。
/// root sub 在 OS 进程结束时随 isolate 清理，无 leak 风险。
library;

import 'dart:async';

import 'package:flutter/services.dart';

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
