import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/testing/fake_resume_storage.dart';

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
}
