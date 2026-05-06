// lib/src/observability/analytics_emitter.dart
import 'package:niuma_player/src/observability/analytics_event.dart';

/// 调用方提供的钩子。niuma_player 在每个内部事件上调用它；
/// 应用将事件转发给自家的 analytics SDK（Sensors / GIO / Bugly / ...）。
typedef AnalyticsEmitter = void Function(AnalyticsEvent event);
