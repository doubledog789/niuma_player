import 'package:flutter/foundation.dart';

/// 标识广告在内容时间轴上的播放位置。
enum AdCueType {
  /// 内容开始前播放的广告。
  preRoll,

  /// 内容中间预定位置播放的广告。
  midRoll,

  /// 用户暂停播放时触发的广告（不是广告自身的暂停行为）。
  pauseAd,

  /// 内容结束后播放的广告。
  postRoll,
}

/// 广告被提前关闭的原因。
enum AdDismissReason {
  /// 用户点击了跳过控件。
  userSkip,

  /// 展示时长达到上限后自动关闭。
  timeout,

  /// 用户点击了广告外部 / 关闭区域而被关闭。
  dismissOnTap,

  /// 广告 builder 抛异常 / 出现内部错误后被强制关闭。区分于 [timeout]，
  /// 避免分析仪表盘把"builder 崩溃"误计成"展示完时长"。
  error,
}

/// niuma_player 内部发出的结构化事件类型；由调用方传入的
/// [AnalyticsEmitter] 消费。
@immutable
sealed class AnalyticsEvent {
  const AnalyticsEvent();

  const factory AnalyticsEvent.adScheduled({
    required AdCueType cueType,
    Duration? at,
  }) = AdScheduled;

  const factory AnalyticsEvent.adImpression({
    required AdCueType cueType,
    required Duration durationShown,
  }) = AdImpression;

  const factory AnalyticsEvent.adClick({
    required AdCueType cueType,
  }) = AdClick;

  const factory AnalyticsEvent.adDismissed({
    required AdCueType cueType,
    required AdDismissReason reason,
  }) = AdDismissed;
}

/// 编排器激活某个 cue 时发出（at-show，尚未计 impression）。
final class AdScheduled extends AnalyticsEvent {
  const AdScheduled({required this.cueType, this.at});

  /// 该次排播广告的位置类别。
  final AdCueType cueType;

  /// 广告排播时距内容起点的偏移；对于非时间轴类位置（如
  /// [AdCueType.pauseAd]）为 null。
  final Duration? at;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdScheduled && other.cueType == cueType && other.at == at;

  @override
  int get hashCode => Object.hash(cueType, at);
}

/// 广告变为可见并开启 impression 计时窗口时触发。
final class AdImpression extends AnalyticsEvent {
  const AdImpression({required this.cueType, required this.durationShown});

  /// 被展示广告的位置类别。
  final AdCueType cueType;

  /// 触发本事件前广告已可见的时长。
  final Duration durationShown;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdImpression &&
          other.cueType == cueType &&
          other.durationShown == durationShown;

  @override
  int get hashCode => Object.hash(cueType, durationShown);
}

/// 用户点击广告的可交互（click-through）区域时触发。
final class AdClick extends AnalyticsEvent {
  const AdClick({required this.cueType});

  /// 被点击广告的位置类别。
  final AdCueType cueType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AdClick && other.cueType == cueType;

  @override
  int get hashCode => cueType.hashCode;
}

/// 广告被关闭时触发，可能由用户操作或自动关闭引起。
final class AdDismissed extends AnalyticsEvent {
  const AdDismissed({required this.cueType, required this.reason});

  /// 被关闭广告的位置类别。
  final AdCueType cueType;

  /// 广告关闭原因。
  final AdDismissReason reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdDismissed && other.cueType == cueType && other.reason == reason;

  @override
  int get hashCode => Object.hash(cueType, reason);
}
