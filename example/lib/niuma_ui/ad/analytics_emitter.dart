import 'analytics_event.dart';

/// 调用方提供的钩子。广告调度参考皮在每个广告事件上调用它；
/// 应用将事件转发给自家的 analytics SDK（Sensors / GIO / Bugly / ...）。
typedef AnalyticsEmitter = void Function(AnalyticsEvent event);
