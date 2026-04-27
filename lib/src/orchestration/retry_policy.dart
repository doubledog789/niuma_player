// lib/src/orchestration/retry_policy.dart
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/player_state.dart';

/// Controls whether and when to retry player initialisation failures.
///
/// Three ready-made policies are available via named constructors:
/// [RetryPolicy.smart], [RetryPolicy.exponential], and [RetryPolicy.none].
/// All instances are immutable and const-constructible.
@immutable
class RetryPolicy {
  const RetryPolicy._({
    required this.maxAttempts,
    required this.base,
    required this.max,
    required this.retryCategories,
  });

  /// The default policy for most apps.
  ///
  /// Retries [PlayerErrorCategory.network] and [PlayerErrorCategory.transient]
  /// errors up to [maxAttempts] times (default 3), using an exponential
  /// back-off starting at 1 s and capped at 10 s.
  const factory RetryPolicy.smart({int maxAttempts}) = _SmartRetry;

  /// Like [RetryPolicy.smart] but allows the caller to tune [base], [max], and
  /// [maxAttempts].
  ///
  /// Retries network and transient errors only.
  const factory RetryPolicy.exponential({
    Duration base,
    Duration max,
    int maxAttempts,
  }) = _ExponentialRetry;

  /// Disables retry entirely — [shouldRetry] always returns `false`.
  const factory RetryPolicy.none() = _NoRetry;

  /// Maximum number of retry attempts before giving up.
  ///
  /// [shouldRetry] returns `false` when `attempt > maxAttempts`.
  final int maxAttempts;

  /// Delay for the first retry; subsequent delays double from this value.
  final Duration base;

  /// Upper bound on the exponential growth computed by [delayFor].
  final Duration max;

  /// The set of [PlayerErrorCategory] values that are eligible for retry.
  ///
  /// Categories absent from this set cause [shouldRetry] to return `false`
  /// regardless of the attempt count.
  final Set<PlayerErrorCategory> retryCategories;

  /// Returns `true` when [category] is retryable and [attempt] has not
  /// exceeded [maxAttempts].
  bool shouldRetry(PlayerErrorCategory category, {required int attempt}) {
    if (attempt > maxAttempts) return false;
    return retryCategories.contains(category);
  }

  /// Computes the back-off delay for the given [attempt] number (1-based).
  ///
  /// The delay doubles with each attempt (`base * 2^(attempt-1)`) and is
  /// capped at [max].
  Duration delayFor(int attempt) {
    final exp = base * pow(2, attempt - 1).toInt();
    return exp > max ? max : exp;
  }
}

class _SmartRetry extends RetryPolicy {
  const _SmartRetry({super.maxAttempts = 3})
      : super._(
          base: const Duration(seconds: 1),
          max: const Duration(seconds: 10),
          retryCategories: const {
            PlayerErrorCategory.network,
            PlayerErrorCategory.transient,
          },
        );
}

class _ExponentialRetry extends RetryPolicy {
  const _ExponentialRetry({
    super.base = const Duration(seconds: 1),
    super.max = const Duration(seconds: 10),
    super.maxAttempts = 3,
  }) : super._(
          retryCategories: const {
            PlayerErrorCategory.network,
            PlayerErrorCategory.transient,
          },
        );
}

class _NoRetry extends RetryPolicy {
  const _NoRetry()
      : super._(
          maxAttempts: 0,
          base: Duration.zero,
          max: Duration.zero,
          retryCategories: const {},
        );
}
