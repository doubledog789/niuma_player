import 'package:niuma_player/src/observability/analytics_event.dart';

/// `AnalyticsEmitter` typedef（`void Function(AnalyticsEvent)`）的捕获型
/// 测试替身。
///
/// 实例会把每次传给 [call] 的 [AnalyticsEvent] 记录到内存列表中。在断言
/// 里读取 [events] 来校验发出过哪些事件以及顺序。
///
/// 由于本类提供了与 `AnalyticsEmitter` typedef 同签名的 [call] 方法，
/// 实例可以直接传给任何需要 `AnalyticsEmitter` 的位置——不需要 wrapper
/// 或适配器。
///
/// 该类仅供测试使用，不得用于生产代码。
class FakeAnalyticsEmitter {
  final List<AnalyticsEvent> _events = [];

  /// 按发出顺序捕获到的事件的不可变视图。
  ///
  /// 用于测试断言，例如：
  /// ```dart
  /// expect(fake.events, hasLength(2));
  /// expect(fake.events.first, isA<AdClick>());
  /// ```
  List<AnalyticsEvent> get events => List.unmodifiable(_events);

  /// 把 [event] 记录到捕获日志中。
  ///
  /// 签名与 `AnalyticsEmitter` typedef
  /// （`void Function(AnalyticsEvent)`）一致，因此 `FakeAnalyticsEmitter`
  /// 实例可以传给任何需要 `AnalyticsEmitter` 的位置。
  void call(AnalyticsEvent event) => _events.add(event);

  /// 清空之前捕获到的全部事件。
  ///
  /// 在测试不同阶段之间调用以重置状态，无需新建实例。
  void clear() => _events.clear();
}
