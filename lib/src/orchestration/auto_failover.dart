import 'package:niuma_player/src/domain/player_state.dart';
import 'package:niuma_player/src/orchestration/multi_source.dart';

/// 初始化失败后决定下一条尝试的 [MediaLine]，按 [MediaLine.priority]
/// 升序遍历；无法 failover 或预算耗尽时 [nextLine] 返 `null`。
class AutoFailoverOrchestrator {
  /// 为 [lines] 创建一个由 [policy] 控制的编排器。
  AutoFailoverOrchestrator({required this.lines, required this.policy});

  /// 可供 failover 的候选播放线路。
  final List<MediaLine> lines;

  /// 控制是否启用 failover 以及最大切换次数的 [MultiSourcePolicy]。
  final MultiSourcePolicy policy;

  int _failovers = 0;

  /// 递增 failover 计数；controller 每次成功切换线路后必须调用。
  void recordFailover() => _failovers++;

  /// 返回下一条要尝试的线路 id（priority 升序中 [currentId] 之后紧邻
  /// 一条）；policy 未启用 / 预算耗尽 / [category] 不可重试（仅 network
  /// 与 terminal 触发）/ 当前已是最后一条时返 `null`。
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
