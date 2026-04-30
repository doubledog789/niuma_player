import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/player_state.dart';

/// 控制播放器初始化失败时是否重试以及何时重试。
///
/// 通过命名构造提供三种现成策略：[RetryPolicy.smart]、
/// [RetryPolicy.exponential]、[RetryPolicy.none]。
/// 所有实例都不可变且支持 const 构造。
@immutable
class RetryPolicy {
  const RetryPolicy._({
    required this.maxAttempts,
    required this.base,
    required this.max,
    required this.retryCategories,
  });

  /// 大多数 app 的默认策略。
  ///
  /// 对 [PlayerErrorCategory.network] 与 [PlayerErrorCategory.transient]
  /// 错误最多重试 [maxAttempts] 次（默认 3），使用从 1 秒开始、上限
  /// 10 秒的指数退避。
  const factory RetryPolicy.smart({int maxAttempts}) = _SmartRetry;

  /// 与 [RetryPolicy.smart] 类似，但允许调用方自定义 [base]、[max] 和
  /// [maxAttempts]。
  ///
  /// 仅重试 network 与 transient 错误。
  const factory RetryPolicy.exponential({
    Duration base,
    Duration max,
    int maxAttempts,
  }) = _ExponentialRetry;

  /// 完全禁用重试——[shouldRetry] 永远返回 `false`。
  const factory RetryPolicy.none() = _NoRetry;

  /// 放弃前的最大重试次数。
  ///
  /// 当 `attempt > maxAttempts` 时 [shouldRetry] 返回 `false`。
  final int maxAttempts;

  /// 第一次重试的延迟；后续延迟在此基础上翻倍。
  final Duration base;

  /// [delayFor] 指数增长的上限。
  final Duration max;

  /// 允许重试的 [PlayerErrorCategory] 集合。
  ///
  /// 不在该集合中的 category 会让 [shouldRetry] 返回 `false`，
  /// 无论 attempt 多少。
  final Set<PlayerErrorCategory> retryCategories;

  /// 当 [category] 可重试且 [attempt] 未超过 [maxAttempts] 时返回
  /// `true`。
  bool shouldRetry(PlayerErrorCategory category, {required int attempt}) {
    if (attempt > maxAttempts) return false;
    return retryCategories.contains(category);
  }

  /// 计算给定 [attempt]（从 1 开始）的退避延迟。
  ///
  /// 每次 attempt 翻倍（`base * 2^(attempt-1)`），上限 [max]。
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
