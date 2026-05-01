import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 单条弹幕的不可变数据。
@immutable
class DanmakuItem {
  /// 构造一条弹幕。
  const DanmakuItem({
    required this.position,
    required this.text,
    this.fontSize = 20.0,
    this.color = const Color(0xFFFFFFFF),
    this.mode = DanmakuMode.scroll,
    this.pool,
    this.metadata,
  });

  /// 出场时刻（视频播放进度）。
  final Duration position;

  /// 文本内容。
  final String text;

  /// 业务原始字号，painter 实际尺寸 = fontSize * settings.fontScale。
  final double fontSize;

  /// 文字颜色。
  final Color color;

  /// 弹幕模式：scroll / topFixed / bottomFixed。
  final DanmakuMode mode;

  /// 业务透传字段（如 server 端 pool 名称）。SDK 不解读。
  final String? pool;

  /// 业务任意附加字段（object_id / sub_id / id / user_id 等）。
  final Object? metadata;

  /// 返回字段更新后的新实例。
  DanmakuItem copyWith({
    Duration? position,
    String? text,
    double? fontSize,
    Color? color,
    DanmakuMode? mode,
    String? pool,
    Object? metadata,
  }) =>
      DanmakuItem(
        position: position ?? this.position,
        text: text ?? this.text,
        fontSize: fontSize ?? this.fontSize,
        color: color ?? this.color,
        mode: mode ?? this.mode,
        pool: pool ?? this.pool,
        metadata: metadata ?? this.metadata,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DanmakuItem &&
          position == other.position &&
          text == other.text &&
          fontSize == other.fontSize &&
          color == other.color &&
          mode == other.mode &&
          pool == other.pool &&
          metadata == other.metadata;

  @override
  int get hashCode =>
      Object.hash(position, text, fontSize, color, mode, pool, metadata);
}

/// 弹幕显示模式。
enum DanmakuMode {
  /// 从右向左滚动。
  scroll,

  /// 顶部居中固定 [DanmakuSettings.fixedDuration]。
  topFixed,

  /// 底部居中固定 [DanmakuSettings.fixedDuration]。
  bottomFixed,
}

/// 弹幕全局设置。
@immutable
class DanmakuSettings {
  /// 构造默认设置。
  const DanmakuSettings({
    this.visible = true,
    this.fontScale = 1.0,
    this.opacity = 1.0,
    this.displayAreaPercent = 1.0,
    this.bucketSize = const Duration(seconds: 60),
    this.scrollDuration = const Duration(seconds: 10),
    this.fixedDuration = const Duration(seconds: 5),
  });

  /// 全局 ON/OFF。
  final bool visible;

  /// 字号倍率 [0.5, 2.0]，painter 实际尺寸 = item.fontSize * fontScale。
  final double fontScale;

  /// 全局不透明度 [0.0, 1.0]。
  final double opacity;

  /// 显示区域占播放器高度的百分比 [0.25, 1.0]，从顶部开始计算（B 站约定）。
  final double displayAreaPercent;

  /// lazy load 桶大小。默认 60s 与后端协议一致。
  final Duration bucketSize;

  /// scroll 模式：单条从右进场到左离场的总时长（速度归一化）。
  final Duration scrollDuration;

  /// topFixed / bottomFixed 模式：固定显示时长。
  final Duration fixedDuration;

  /// 返回字段更新后的新实例。
  DanmakuSettings copyWith({
    bool? visible,
    double? fontScale,
    double? opacity,
    double? displayAreaPercent,
    Duration? bucketSize,
    Duration? scrollDuration,
    Duration? fixedDuration,
  }) =>
      DanmakuSettings(
        visible: visible ?? this.visible,
        fontScale: fontScale ?? this.fontScale,
        opacity: opacity ?? this.opacity,
        displayAreaPercent: displayAreaPercent ?? this.displayAreaPercent,
        bucketSize: bucketSize ?? this.bucketSize,
        scrollDuration: scrollDuration ?? this.scrollDuration,
        fixedDuration: fixedDuration ?? this.fixedDuration,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DanmakuSettings &&
          visible == other.visible &&
          fontScale == other.fontScale &&
          opacity == other.opacity &&
          displayAreaPercent == other.displayAreaPercent &&
          bucketSize == other.bucketSize &&
          scrollDuration == other.scrollDuration &&
          fixedDuration == other.fixedDuration;

  @override
  int get hashCode => Object.hash(
        visible,
        fontScale,
        opacity,
        displayAreaPercent,
        bucketSize,
        scrollDuration,
        fixedDuration,
      );
}

/// 60s 桶 lazy loader 签名。SDK 在跨入新桶时调用。
typedef DanmakuLoader = FutureOr<List<DanmakuItem>> Function(
  Duration bucketStart,
  Duration bucketEnd,
);
