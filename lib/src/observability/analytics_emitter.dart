// lib/src/observability/analytics_emitter.dart
import 'analytics_event.dart';

/// User-supplied hook. niuma_player calls this on every internal event;
/// app forwards to its own analytics SDK (Sensors / GIO / Bugly / ...).
typedef AnalyticsEmitter = void Function(AnalyticsEvent event);
