import '../domain/player_state.dart';
import 'multi_source.dart';

/// Decides which [MediaLine] to try next after an initialisation failure.
///
/// Consulted by the controller after a failed `initialize` to determine
/// whether to retry on a different [MediaLine]. Lines are walked in
/// ascending [MediaLine.priority] order (lower number = tried first).
/// Returns `null` when failover is not possible or the attempt budget is
/// exhausted.
class AutoFailoverOrchestrator {
  /// Creates an orchestrator for [lines] governed by [policy].
  AutoFailoverOrchestrator({required this.lines, required this.policy});

  /// The candidate playback lines available for failover.
  final List<MediaLine> lines;

  /// The [MultiSourcePolicy] that controls whether failover is enabled and
  /// how many switch attempts are permitted.
  final MultiSourcePolicy policy;

  int _failovers = 0;

  /// Increments the internal failover counter.
  ///
  /// The controller must call this after each successful line switch so that
  /// [nextLine] can enforce [MultiSourcePolicy.maxAttempts].
  void recordFailover() => _failovers++;

  /// Returns the id of the next line to try, or `null` if no switch should
  /// occur.
  ///
  /// Returns `null` when:
  /// - [policy] is disabled,
  /// - the failover counter has reached [MultiSourcePolicy.maxAttempts],
  /// - [category] is not retriable (only [PlayerErrorCategory.network] and
  ///   [PlayerErrorCategory.terminal] trigger a switch),
  /// - [currentId] is not found in [lines], or
  /// - the current line is already the last in ascending-priority order.
  ///
  /// Lines are sorted ascending by [MediaLine.priority] (lower number tried
  /// first); the next line is the immediate successor of [currentId] in that
  /// ordering.
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
