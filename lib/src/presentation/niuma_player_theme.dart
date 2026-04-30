import 'package:flutter/material.dart';

/// niuma_player UI 层的不可变主题数据。
///
/// 字段集覆盖控件栏、进度条、缩略图预览、过渡动画的可调点，所有字段
/// 都有合理的默认值——默认外观即 B 站风格密集底栏，调用方按需覆盖。
///
/// 通过把实例放入 [NiumaPlayerThemeData]（一个 [InheritedWidget]）将
/// 主题注入 widget 树，控件用 [NiumaPlayerTheme.of] 在 build 时读取。
/// 没有 inherited 时返回默认实例（[NiumaPlayerTheme]），所以最简单
/// 用法是直接 `NiumaPlayer(controller: ctl)` 不传 theme。
@immutable
class NiumaPlayerTheme {
  /// 创建一个 [NiumaPlayerTheme]。
  ///
  /// 所有字段都是可选的——不传任何字段得到的就是 niuma_player 默认外观。
  const NiumaPlayerTheme({
    this.accentColor,
    this.iconColor = Colors.white,
    this.iconSize = 24,
    this.bigIconSize = 36,
    this.controlBarPadding =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.scrubBarHeight = 4,
    this.scrubBarThumbRadius = 6,
    this.scrubBarThumbRadiusActive = 9,
    this.bufferedFillColor,
    this.thumbnailPreviewSize = const Size(160, 90),
    this.fadeInDuration = const Duration(milliseconds: 200),
    this.controlsBackgroundGradient = const [
      Colors.transparent,
      Colors.black87,
    ],
    this.timeTextStyle = const TextStyle(
      color: Colors.white,
      fontFeatures: [FontFeature.tabularFigures()],
      fontSize: 12,
    ),
  });

  /// 强调色。
  ///
  /// **生效范围**：仅作用于"需要强调状态"的渲染——目前包含
  /// [ScrubBar] 的 active 段填充（已播部分）和拖动 thumb 的颜色。
  /// **不**作用于普通图标按钮——主控件栏的 PlayPause / Volume /
  /// Fullscreen 等图标按钮统一使用 [iconColor]，不读 accentColor。
  /// 若希望整套图标也跟着主题色变，请同时调 [iconColor]。
  ///
  /// `null` 时控件应回退到 `Theme.of(context).primaryColor`，让 host
  /// app 的 Material theme 接管色彩调性。
  final Color? accentColor;

  /// 控件栏中图标的默认前景色。
  final Color iconColor;

  /// 普通图标按钮的尺寸。
  final double iconSize;

  /// "大"图标按钮（例如中心 play / pause overlay）的尺寸。
  final double bigIconSize;

  /// 控件栏外围 padding。
  final EdgeInsetsGeometry controlBarPadding;

  /// 进度条主轨道的高度。
  final double scrubBarHeight;

  /// 进度条 thumb（圆点）静止时的半径。
  final double scrubBarThumbRadius;

  /// 进度条 thumb 在拖动 / hover 时放大后的半径。
  final double scrubBarThumbRadiusActive;

  /// "已缓冲段"的填充色。
  ///
  /// `null` 时控件应回退到一个相对柔和的派生色（例如 `iconColor` 半透明）。
  final Color? bufferedFillColor;

  /// 缩略图悬浮预览的目标尺寸。
  final Size thumbnailPreviewSize;

  /// 控件淡入 / 淡出过渡的时长。
  final Duration fadeInDuration;

  /// 控件背景使用的渐变色列表。
  ///
  /// 默认从透明渐变到 black87，让控件叠在视频内容上仍能有可读性。
  final List<Color> controlsBackgroundGradient;

  /// 时间显示（mm:ss / mm:ss）使用的 TextStyle。
  final TextStyle timeTextStyle;

  /// 静态查找：从 widget 树中沿祖先方向找最近的 [NiumaPlayerThemeData]，
  /// 没有则返回默认 [NiumaPlayerTheme] 实例。
  ///
  /// 控件 build 中调用：
  /// ```dart
  /// final theme = NiumaPlayerTheme.of(context);
  /// ```
  static NiumaPlayerTheme of(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<NiumaPlayerThemeData>();
    return inherited?.data ?? const NiumaPlayerTheme();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NiumaPlayerTheme) return false;
    return other.accentColor == accentColor &&
        other.iconColor == iconColor &&
        other.iconSize == iconSize &&
        other.bigIconSize == bigIconSize &&
        other.controlBarPadding == controlBarPadding &&
        other.scrubBarHeight == scrubBarHeight &&
        other.scrubBarThumbRadius == scrubBarThumbRadius &&
        other.scrubBarThumbRadiusActive == scrubBarThumbRadiusActive &&
        other.bufferedFillColor == bufferedFillColor &&
        other.thumbnailPreviewSize == thumbnailPreviewSize &&
        other.fadeInDuration == fadeInDuration &&
        _listEquals(other.controlsBackgroundGradient,
            controlsBackgroundGradient) &&
        other.timeTextStyle == timeTextStyle;
  }

  @override
  int get hashCode => Object.hash(
        accentColor,
        iconColor,
        iconSize,
        bigIconSize,
        controlBarPadding,
        scrubBarHeight,
        scrubBarThumbRadius,
        scrubBarThumbRadiusActive,
        bufferedFillColor,
        thumbnailPreviewSize,
        fadeInDuration,
        Object.hashAll(controlsBackgroundGradient),
        timeTextStyle,
      );
}

/// 沿用 [Object.==] 之外的逐元素比较，因为 List 的默认 equality 是
/// 引用相等。
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 把 [NiumaPlayerTheme] 注入 widget 树的 [InheritedWidget]。
///
/// 用法：
/// ```dart
/// NiumaPlayerThemeData(
///   data: NiumaPlayerTheme(accentColor: Colors.deepPurple),
///   child: NiumaPlayer(controller: controller),
/// )
/// ```
class NiumaPlayerThemeData extends InheritedWidget {
  /// 创建一个 [NiumaPlayerThemeData]。
  const NiumaPlayerThemeData({
    super.key,
    required this.data,
    required super.child,
  });

  /// 注入到 widget 树中的主题数据。
  final NiumaPlayerTheme data;

  @override
  bool updateShouldNotify(NiumaPlayerThemeData oldWidget) =>
      data != oldWidget.data;
}
