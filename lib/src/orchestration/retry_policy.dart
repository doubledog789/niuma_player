import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:niuma_player/src/domain/player_state.dart';

/// 控制播放器初始化失败时是否重试以及何时重试；现成策略见
/// [RetryPolicy.smart] / [RetryPolicy.exponential] / [RetryPolicy.none]。
@immutable
class RetryPolicy {
  const RetryPolicy._({
    required this.maxAttempts,
    required this.base,
    required this.max,
    required this.retryCategories,
  });

  /// 默认策略：network / transient 错误最多重试 [maxAttempts] 次
  /// （默认 3），1s 起步、上限 10s 的指数退避。
  const factory RetryPolicy.smart({int maxAttempts}) = _SmartRetry;

  /// 同 [RetryPolicy.smart] 但可自定义 [base] / [max] / [maxAttempts]。
  const factory RetryPolicy.exponential({
    Duration base,
    Duration max,
    int maxAttempts,
  }) = _ExponentialRetry;

  /// 完全禁用重试——[shouldRetry] 永远返回 `false`。
  const factory RetryPolicy.none() = _NoRetry;

  /// 放弃前的最大重试次数；`attempt > maxAttempts` 时不再重试。
  final int maxAttempts;

  /// 第一次重试的延迟；后续延迟在此基础上翻倍。
  final Duration base;

  /// [delayFor] 指数增长的上限。
  final Duration max;

  /// 允许重试的 [PlayerErrorCategory] 集合，之外的一律不重试。
  final Set<PlayerErrorCategory> retryCategories;

  /// [category] 可重试且 [attempt] 未超 [maxAttempts] 时返回 `true`。
  bool shouldRetry(PlayerErrorCategory category, {required int attempt}) {
    if (attempt > maxAttempts) return false;
    return retryCategories.contains(category);
  }

  /// 第 [attempt] 次（从 1 起）的退避延迟：`base * 2^(attempt-1)`，上限 [max]。
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
