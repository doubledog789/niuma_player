import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/orchestration/resume_position.dart';
import 'package:niuma_player/src/testing/fake_resume_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('FakeResumeStorage round-trips a position', () async {
    final s = FakeResumeStorage();
    expect(await s.read('k'), isNull);
    await s.write('k', const Duration(seconds: 30));
    expect(await s.read('k'), const Duration(seconds: 30));
    await s.clear('k');
    expect(await s.read('k'), isNull);
  });

  test('FakeResumeStorage isolates keys', () async {
    final s = FakeResumeStorage();
    await s.write('a', const Duration(seconds: 5));
    await s.write('b', const Duration(seconds: 10));
    expect(await s.read('a'), const Duration(seconds: 5));
    expect(await s.read('b'), const Duration(seconds: 10));
  });

  test('SharedPreferencesResumeStorage round-trips via SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    const s = SharedPreferencesResumeStorage();

    await s.write('video:abc', const Duration(seconds: 42));
    expect(await s.read('video:abc'), const Duration(seconds: 42));

    await s.clear('video:abc');
    expect(await s.read('video:abc'), isNull);
  });

  test('ResumePolicy defaults', () {
    const p = ResumePolicy();
    expect(p.behaviour, ResumeBehaviour.auto);
    expect(p.minSavedPosition, const Duration(seconds: 30));
    expect(p.discardIfNearEnd, const Duration(seconds: 30));
    expect(p.savePeriod, const Duration(seconds: 5));
  });

  test('ResumePolicy.defaultKeyOf hashes uri', () {
    final ds = NiumaDataSource.network('https://cdn/x.mp4');
    expect(defaultResumeKey(ds), 'video:https://cdn/x.mp4');
  });

  test('ResumeOrchestrator reads on init and seeks to saved position', () async {
    final storage = FakeResumeStorage();
    await storage.write('key', const Duration(seconds: 42));

    Duration? seekTarget;
    final ds = NiumaDataSource.network('https://x');
    final orch = ResumeOrchestrator(
      policy: ResumePolicy(
        storage: storage,
        keyOf: (_) => 'key',
      ),
      source: ds,
      seekTo: (d) async => seekTarget = d,
      currentPosition: () => Duration.zero,
    );

    await orch.onInitialized();
    expect(seekTarget, const Duration(seconds: 42));
  });

  test('ResumeOrchestrator does not write before minSavedPosition', () {
    fakeAsync((async) {
      final storage = FakeResumeStorage();
      var pos = Duration.zero;
      final orch = ResumeOrchestrator(
        policy: ResumePolicy(
          storage: storage,
          keyOf: (_) => 'k',
          minSavedPosition: const Duration(seconds: 30),
          savePeriod: const Duration(seconds: 5),
        ),
        source: NiumaDataSource.network('x'),
        seekTo: (_) async {},
        currentPosition: () => pos,
      )..startPeriodicSave();

      pos = const Duration(seconds: 10);
      async.elapse(const Duration(seconds: 6));
      expect(storage.snapshot, isEmpty);

      pos = const Duration(seconds: 31);
      async.elapse(const Duration(seconds: 6));
      expect(storage.snapshot['k'], const Duration(seconds: 31));

      orch.dispose();
    });
  });

  test('ResumeOrchestrator.onEnded clears the saved entry', () async {
    final storage = FakeResumeStorage();
    await storage.write('k', const Duration(seconds: 42));
    final orch = ResumeOrchestrator(
      policy: ResumePolicy(
        storage: storage,
        keyOf: (_) => 'k',
      ),
      source: NiumaDataSource.network('x'),
      seekTo: (_) async {},
      currentPosition: () => Duration.zero,
    );
    await orch.onEnded();
    expect(await storage.read('k'), isNull,
        reason: 'phase=ended must clear the saved resume entry');
  });

  test(
      'ResumeOrchestrator.dispose writes a final position when '
      '>= minSavedPosition', () async {
    final storage = FakeResumeStorage();
    final orch = ResumeOrchestrator(
      policy: ResumePolicy(
        storage: storage,
        keyOf: (_) => 'k',
        minSavedPosition: const Duration(seconds: 30),
      ),
      source: NiumaDataSource.network('x'),
      seekTo: (_) async {},
      currentPosition: () => const Duration(seconds: 45),
    );
    await orch.dispose();
    expect(await storage.read('k'), const Duration(seconds: 45),
        reason: 'dispose() must persist the final position');
  });

  test(
      'ResumeOrchestrator.dispose does NOT write below minSavedPosition',
      () async {
    final storage = FakeResumeStorage();
    final orch = ResumeOrchestrator(
      policy: ResumePolicy(
        storage: storage,
        keyOf: (_) => 'k',
        minSavedPosition: const Duration(seconds: 30),
      ),
      source: NiumaDataSource.network('x'),
      seekTo: (_) async {},
      currentPosition: () => const Duration(seconds: 5),
    );
    await orch.dispose();
    expect(await storage.read('k'), isNull,
        reason: 'dispose at <minSavedPosition must not persist');
  });
}
