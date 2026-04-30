import '../domain/player_state.dart';
import 'multi_source.dart';

/// 在初始化失败后决定下一条尝试的 [MediaLine]。
///
/// controller 在 `initialize` 失败后调用，用以判断是否切换到另一条
/// [MediaLine] 重试。按 [MediaLine.priority] 升序遍历（数字越小越早
/// 尝试）。当无法 failover 或重试预算耗尽时返回 `null`。
class AutoFailoverOrchestrator {
  /// 为 [lines] 创建一个由 [policy] 控制的编排器。
  AutoFailoverOrchestrator({required this.lines, required this.policy});

  /// 可供 failover 的候选播放线路。
  final List<MediaLine> lines;

  /// 控制是否启用 failover 以及最大切换次数的 [MultiSourcePolicy]。
  final MultiSourcePolicy policy;

  int _failovers = 0;

  /// 递增内部 failover 计数。
  ///
  /// controller 必须在每次成功切换线路后调用，使 [nextLine] 能够正确
  /// 校验 [MultiSourcePolicy.maxAttempts]。
  void recordFailover() => _failovers++;

  /// 返回下一条要尝试的线路 id；若不应切换则返回 `null`。
  ///
  /// 以下情况返回 `null`：
  /// - [policy] 未启用；
  /// - failover 计数已达 [MultiSourcePolicy.maxAttempts]；
  /// - [category] 不可重试（只有 [PlayerErrorCategory.network] 和
  ///   [PlayerErrorCategory.terminal] 会触发切换）；
  /// - [currentId] 不在 [lines] 中；
  /// - 当前线路在升序优先级中已是最后一条。
  ///
  /// 线路按 [MediaLine.priority] 升序排序（数字越小越早尝试）；下一条
  /// 即为该顺序中 [currentId] 之后紧邻的那条。
  String? nextLine({
    required String currentId,
    required PlayerErrorCategory category,
  }) {
    if (!policy.enabled) return null;
    if (_failovers >= policy.maxAttempts) return null;
    if (category != PlayerErrorCategory.network &&
        category != PlayerErrorCategory.terminal) {
      return null;
    }

    final sorted = [...lines]..sort((a, b) => a.priority.compareTo(b.priority));
    final currentIdx = sorted.indexWhere((l) => l.id == currentId);
    if (currentIdx == -1) return null;
    if (currentIdx + 1 >= sorted.length) return null;
    return sorted[currentIdx + 1].id;
  }
}
