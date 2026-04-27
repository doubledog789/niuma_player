import '../orchestration/resume_position.dart';

/// In-memory [ResumeStorage] test double for use in widget and unit tests.
///
/// All state is held in a plain [Map] — nothing is persisted to disk. Export
/// this class via `lib/testing.dart` (or import directly from
/// `package:niuma_player/src/testing/fake_resume_storage.dart`) in your own
/// widget tests to inject a controllable storage backend without touching the
/// file system or shared preferences.
///
/// Uses `implements` rather than `extends` so that any future protected
/// behaviour added to [ResumeStorage] does not leak into this test double.
class FakeResumeStorage implements ResumeStorage {
  final Map<String, Duration> _store = {};

  @override
  Future<Duration?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, Duration position) async {
    _store[key] = position;
  }

  @override
  Future<void> clear(String key) async {
    _store.remove(key);
  }

  /// A read-only snapshot of the current in-memory store.
  ///
  /// Useful in test assertions to verify the exact contents of storage
  /// without going through the [read] API.
  Map<String, Duration> get snapshot => Map.unmodifiable(_store);
}
