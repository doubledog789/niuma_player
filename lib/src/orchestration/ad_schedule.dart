// lib/src/orchestration/ad_schedule.dart
import 'package:flutter/widgets.dart';

/// 广告 widget 与广告系统之间的契约。
///
/// 业务 widget 通过 [AdCue.builder] 回调拿到 [AdController] 实例，
/// 用它控制自身的关闭以及上报埋点事件（impression、click）。具体
/// 实现是 `AdControllerImpl`（Task 19 + 后续接线任务）——目前
/// 编排器只负责发出 `activeCue`，宿主 overlay 自行实例化
/// `AdControllerImpl` 并把它接到 [AdCue.builder] 中。M9 会把这部分
/// 收回到编排器内。
abstract class AdController {
  /// 关闭广告。在 [AdCue.minDisplayDuration] 之前的调用，在 release
  /// 构建中静默忽略，在 debug 构建中 assert。
  void dismiss();

  /// 广告当前已展示的累计时长。
  Duration get elapsed;

  /// 每个 tick 都广播一次最新 [elapsed] 值的 broadcast stream。
  ///
  /// 典型用途：在广告 widget 中驱动倒计时，让观众看到还有多久才能
  /// 关闭 overlay。
  Stream<Duration> get elapsedStream;

  /// 触发 fire-and-forget 的 impression 事件。
  ///
  /// [AdSchedulerOrchestrator] 会将其转发给 [AnalyticsEmitter]。
  /// 调用方应在广告变可见时调用一次。
  void reportImpression();

  /// 触发 fire-and-forget 的 click 事件。
  ///
  /// [AdSchedulerOrchestrator] 会将其转发给 [AnalyticsEmitter]。
  /// 调用方应在观众与广告 call-to-action 交互时调用。
  void reportClick();
}

/// 一个可展示的广告载荷。
///
/// [AdCue] 不绑定具体载荷：实际 widget 由 [builder] 按需生产，回调
/// 接收 [BuildContext] 和 [AdController]。
/// 排播元数据（[minDisplayDuration]、[timeout]、[dismissOnTap]）与
/// builder 并列声明，让广告系统无需检查 widget tree 即可执行时序规则。
@immutable
class AdCue {
  /// 创建一个 [AdCue]。
  ///
  /// 只有 [builder] 必填；所有时序字段都有合理默认值。
  const AdCue({
    required this.builder,
    this.minDisplayDuration = const Duration(seconds: 5),
    this.timeout,
    this.dismissOnTap = false,
  });

  /// 本广告的 widget 渲染函数。
  ///
  /// 接收 [BuildContext] 和 [AdController]。controller 让 widget 自己
  /// 关闭并上报埋点；使用它而不是直接 navigate 或调用系统级 pop。
  final Widget Function(BuildContext, AdController) builder;

  /// 广告必须先展示的最短时长，未到该时长不允许关闭。
  ///
  /// 在该时长之前的 [AdController.dismiss] 调用，在 release 构建中
  /// 静默忽略，在 debug 构建中触发 assertion 失败。默认 5 秒。
  final Duration minDisplayDuration;

  /// 可选的最长展示时长，超过则自动关闭。
  ///
  /// 当 [timeout] 非 null 且广告可见时长达到该值，
  /// [AdSchedulerOrchestrator] 会自动关闭它。`null`（默认）意味着
  /// 广告自身永远不会超时。
  final Duration? timeout;

  /// 点击广告 overlay 任意位置是否会关闭它。
  ///
  /// `true` 时，宿主广告 overlay（M9 由 `NiumaVideoPlayer` 渲染）
  /// 会用一个吞掉点击事件并调用 [AdController.dismiss] 的 gesture
  /// detector 包住广告。`false`（默认）时，点击事件透传给 [builder]
  /// 渲染的内容——大多数广告会自带关闭按钮。
  final bool dismissOnTap;
}

/// 控制 mid-roll cue 在 seek 或循环播放时的行为。
///
/// 作为 [MidRollAd.skipPolicy] 传入，用以配置 seek 跳过 cue 的
/// [MidRollAd.at] 位置时是否抑制该广告。
enum MidRollSkipPolicy {
  /// 一旦广告被展示过，就再也不会展示——即使是回放或循环。
  fireOnce,

  /// 每次播放跨过 [MidRollAd.at] 都触发，包括回放后以及循环内容。
  fireEachPass,

  /// 如果观众通过 seek 跳过 [MidRollAd.at] 而非正常播放跨过它，则
  /// 该次 seek 中抑制广告。这是默认值，匹配抖音 / B 站 / 优酷的行为。
  skipIfSeekedPast,
}

/// 控制观众手动暂停时 pause 广告的展示频率。
///
/// 赋给 [NiumaAdSchedule.pauseAdShowPolicy]。
enum PauseAdShowPolicy {
  /// 每次手动暂停都展示 pause 广告。
  always,

  /// 每个播放会话最多展示一次 pause 广告（默认）。
  oncePerSession,

  /// 每个 [NiumaAdSchedule.pauseAdCooldown] 窗口内最多展示一次。
  /// 每次实际展示都会重置 cooldown。
  cooldown,
}

/// 锚定到时间轴特定位置的 mid-roll 广告 cue。
///
/// [MidRollAd] 把 [AdCue] 载荷与播放偏移 [at]、决定 seek 跳过时是否
/// 触发的 [skipPolicy] 绑在一起。实例放在 [NiumaAdSchedule.midRolls]
/// 中，由调用方负责按 [at] 升序排序。
@immutable
class MidRollAd {
  /// 创建一个 [MidRollAd]。
  ///
  /// [at] 和 [cue] 必填；[skipPolicy] 默认
  /// [MidRollSkipPolicy.skipIfSeekedPast]。
  const MidRollAd({
    required this.at,
    required this.cue,
    this.skipPolicy = MidRollSkipPolicy.skipIfSeekedPast,
  });

  /// 触发本广告的播放位置。
  ///
  /// 编排器在每次 position tick 上比较当前 position 与 [at]。必须是
  /// 正的有限 duration。
  final Duration at;

  /// 播放到 [at] 时要展示的广告载荷。
  final AdCue cue;

  /// 控制 seek 跳过 [at] 时是否抑制该次广告。
  ///
  /// 默认 [MidRollSkipPolicy.skipIfSeekedPast]。
  final MidRollSkipPolicy skipPolicy;
}

/// 声明单次播放会话的所有广告槽位以及 pause 广告频率。
///
/// [NiumaAdSchedule] 是一个纯数据袋，由 [AdSchedulerOrchestrator]
/// （Task 19）消费。它涵盖四个不同的广告槽位——pre-roll、mid-rolls、
/// pause、post-roll——外加一个限制 pause 广告出现频率的策略。
///
/// 示例：
/// ```dart
/// NiumaAdSchedule(
///   preRoll: AdCue(builder: (ctx, ctrl) => MyPreRollWidget(ctrl)),
///   midRolls: [
///     MidRollAd(at: Duration(minutes: 5), cue: AdCue(builder: …)),
///   ],
///   pauseAdShowPolicy: PauseAdShowPolicy.cooldown,
///   pauseAdCooldown: Duration(minutes: 3),
/// )
/// ```
@immutable
class NiumaAdSchedule {
  /// 创建一个 [NiumaAdSchedule]。
  ///
  /// 所有字段都是可选的；都不传得到的就是没有任何广告的排期。
  const NiumaAdSchedule({
    this.preRoll,
    this.midRolls = const <MidRollAd>[],
    this.pauseAd,
    this.postRoll,
    this.pauseAdShowPolicy = PauseAdShowPolicy.oncePerSession,
    this.pauseAdCooldown = const Duration(minutes: 1),
  });

  /// 在首次进入 `phase=ready` 时（播放开始前）触发的广告。`null`
  /// 表示无 pre-roll。
  final AdCue? preRoll;

  /// 锚定到时间轴的 mid-roll cue。
  ///
  /// **必须按 [MidRollAd.at] 升序排序**——由调用方负责。
  /// 编排器做线性扫描，依赖排序保证效率。默认空列表。
  final List<MidRollAd> midRolls;

  /// 观众手动暂停时触发的广告。
  ///
  /// 展示频率由 [pauseAdShowPolicy] 控制。`null` 表示无 pause 广告。
  final AdCue? pauseAd;

  /// `phase=ended` 时（内容播放到尾）触发的广告。`null` 表示无
  /// post-roll。
  final AdCue? postRoll;

  /// 控制 [pauseAd] 展示频率的策略。
  ///
  /// 默认 [PauseAdShowPolicy.oncePerSession]。
  final PauseAdShowPolicy pauseAdShowPolicy;

  /// 两次相邻 pause 广告展示之间的最小间隔。
  ///
  /// 仅在 [pauseAdShowPolicy] 为 [PauseAdShowPolicy.cooldown] 时
  /// 生效。默认 1 分钟。
  final Duration pauseAdCooldown;
}
