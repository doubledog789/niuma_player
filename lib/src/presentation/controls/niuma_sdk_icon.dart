import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// SDK 内部统一的 SVG 图标渲染器。
///
/// 把 [SvgPicture.asset] + 尺寸 + [ColorFilter] 三件套封一层，让所有控件
/// 看起来对齐。**仅供 SDK 内部 controls 使用**——不在公共 API 暴露。
///
/// 测试代码通过 `find.byWidgetPredicate((w) => w is NiumaSdkIcon && w.asset == ...)`
/// 直接在 widget 树上找到对应图标。
class NiumaSdkIcon extends StatelessWidget {
  const NiumaSdkIcon({
    super.key,
    required this.asset,
    this.size = 24,
    this.color,
  });

  final String asset;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFFFFFFFF);
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
    );
  }
}
