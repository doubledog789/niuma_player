// test/orchestration/retry_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/orchestration/retry_policy.dart';

void main() {
  test('RetryPolicy.smart retries network + transient, skips codec/terminal', () {
    const p = RetryPolicy.smart();
    expect(p.shouldRetry(PlayerErrorCategory.network, attempt: 1), isTrue);
    expect(p.shouldRetry(PlayerErrorCategory.transient, attempt: 1), isTrue);
    expect(p.shouldRetry(PlayerErrorCategory.codecUnsupported, attempt: 1),
        isFalse);
    expect(p.shouldRetry(PlayerErrorCategory.terminal, attempt: 1), isFalse);
  });

  test('RetryPolicy.smart caps at maxAttempts (default 3)', () {
    const p = RetryPolicy.smart();
    expect(p.shouldRetry(PlayerErrorCategory.network, attempt: 3), isTrue);
    expect(p.shouldRetry(PlayerErrorCategory.network, attempt: 4), isFalse);
  });

  test('RetryPolicy.exponential backoff doubles up to max', () {
    const p = RetryPolicy.exponential(
      base: Duration(seconds: 1),
      max: Duration(seconds: 10),
    );
    expect(p.delayFor(1), const Duration(seconds: 1));
    expect(p.delayFor(2), const Duration(seconds: 2));
    expect(p.delayFor(3), const Duration(seconds: 4));
    expect(p.delayFor(4), const Duration(seconds: 8));
    expect(p.delayFor(5), const Duration(seconds: 10)); // capped
  });

  test('RetryPolicy.none never retries', () {
    const p = RetryPolicy.none();
    expect(p.shouldRetry(PlayerErrorCategory.network, attempt: 1), isFalse);
  });
}
