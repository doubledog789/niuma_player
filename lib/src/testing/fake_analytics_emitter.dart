// lib/src/testing/fake_analytics_emitter.dart
import '../observability/analytics_event.dart';

/// A capturing test double for the `AnalyticsEmitter` typedef
/// (`void Function(AnalyticsEvent)`).
///
/// Instances record every [AnalyticsEvent] passed to [call] into an
/// in-memory list. Expose [events] in assertions to verify which events
/// were emitted and in what order.
///
/// Because this class exposes a [call] method with the same signature as the
/// `AnalyticsEmitter` typedef, instances can be passed directly wherever an
/// `AnalyticsEmitter` is required — no wrapper or adapter needed.
///
/// This class is intended solely for use in tests; it must not be used in
/// production code.
class FakeAnalyticsEmitter {
  final List<AnalyticsEvent> _events = [];

  /// An unmodifiable view of the events captured so far, in emission order.
  ///
  /// Use this in test assertions, e.g.:
  /// ```dart
  /// expect(fake.events, hasLength(2));
  /// expect(fake.events.first, isA<AdClick>());
  /// ```
  List<AnalyticsEvent> get events => List.unmodifiable(_events);

  /// Records [event] in the capture log.
  ///
  /// The signature matches the `AnalyticsEmitter` typedef
  /// (`void Function(AnalyticsEvent)`), so a `FakeAnalyticsEmitter` instance
  /// can be passed wherever an `AnalyticsEmitter` is required.
  void call(AnalyticsEvent event) => _events.add(event);

  /// Clears all previously captured events.
  ///
  /// Call this between test phases to reset state without creating a new
  /// instance.
  void clear() => _events.clear();
}
